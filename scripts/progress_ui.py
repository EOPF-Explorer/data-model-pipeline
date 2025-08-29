#!/usr/bin/env python3
"""
Stream converter logs, print a compact progress summary, and show the Argo UI URL.

This script starts (or reuses) a local HTTP proxy that injects Authorization headers
for the Argo UI, then prints its URL (http://127.0.0.1:<port>). No kubectl port-forwarding
or token juggling is needed—open the printed link and you are in.
"""

import re
import sys
import hashlib
import os
import subprocess
import socket
import time

pat_input = re.compile(r"Loading dataset from:\s*(?P<url>\S+)")
pat_group = re.compile(r"Processing group(?:\s*for GeoZarr compliance)?:\s*(?P<grp>\S+)")
pat_group2 = re.compile(r"Processing\s+'?(?P<grp>/[^']+?)'? as GeoZarr group")
pat_band = re.compile(r"Writing data variable\s+(?P<band>[^.]+)\.\.\.|Processing band:\s+(?P<band2>\S+)")
pat_overv_ok = re.compile(r"Level\s+(?P<lvl>\d+):\s+Successfully created")
pat_output = re.compile(r"Output saved to:\s*(?P<path>\S+)")
pat_error = re.compile(r"(Error during conversion|ERROR at line|Traceback)")
pat_done = re.compile(r"(Successfully converted EOPF dataset to GeoZarr|Done\.)$")
pat_convert_err = re.compile(r"Error during conversion:?\s*(?P<msg>.+)")
pat_argo_rpc = re.compile(r"rpc error: code =\s*(?P<code>\w+)\s+desc =\s*(?P<desc>.+)")
pat_http_err = re.compile(r"\b(5\d\d|4\d\d)\b")

state = {
    "input": None,
    "groups": [],
    "bands": set(),
    "overviews": set(),
    "output": None,
    "errors": 0,
    "done": False,
    "last_error": None,
}
last_sig = None


def short(s, n=96):
    """Return s truncated to n characters with an ellipsis for tidy, one-line output."""
    return (s[: n - 1] + "…") if s and len(s) > n else s


def sig():
    """Stable fingerprint of the current progress state to avoid noisy reprints."""
    g = tuple(state["groups"][-3:])
    b = tuple(sorted(list(state["bands"]))[-10:])
    o = tuple(sorted(int(x) for x in state["overviews"]))
    data = (state["input"], g, b, o, bool(state["output"]), state["errors"], state["done"], state.get("last_error"))
    return hashlib.md5(repr(data).encode()).hexdigest()


def render():
    """Print a non-repetitive, readable summary of the ongoing conversion."""
    global last_sig
    s = sig()
    if s == last_sig:
        return
    last_sig = s
    lines = []
    if state["input"]:
        lines.append(f"📂 Input:  {short(state['input'])}")
    if state["output"]:
        lines.append(f"🎯 Output: {state['output']}")
    uniq = []
    for g in state["groups"]:
        if not uniq or uniq[-1] != g:
            uniq.append(g)
    if uniq:
        lines.append("Groups: " + " → ".join(uniq[-2:]))
    if state["bands"]:
        bands = sorted(state["bands"])
        lines.append("Bands: " + ", ".join(bands[-5:]))
    if state["overviews"]:
        levels = sorted(int(x) for x in state["overviews"])
        lines.append("Overviews: " + " ".join(f"L{lvl}✅" for lvl in levels))
    if state["errors"]:
        lines.append(f"⚠️  Errors: {state['errors']} (auto-retry may apply)")
        if state.get("last_error"):
            el = state["last_error"].strip()
            if len(el) > 160:
                el = el[:157] + "…"
            lines.append(f"   Last error: {el}")
    if state["done"]:
        lines.append("✅ Conversion complete.")
    print("\n".join(lines), flush=True)


## We exclusively rely on a local auth-injecting HTTP proxy for the Argo UI.


def _start_auth_proxy_bg(ns: str) -> str | None:
    """Start or reuse the local Argo UI proxy.

    Returns:
        The proxy URL (e.g., "http://127.0.0.1:<port>") when ready, otherwise None.
    """
    work = os.path.join(os.getcwd(), ".work")
    os.makedirs(work, exist_ok=True)
    port_file = os.path.join(work, "argo_ui_proxy.port")
    # Fast path: if the port file exists and the port is open, reuse it.
    try:
        if os.path.exists(port_file):
            with open(port_file, "r", encoding="utf-8") as f:
                p = f.read().strip()
            if p.isdigit():
                try:
                    with socket.create_connection(("127.0.0.1", int(p)), timeout=0.3):
                        return f"http://127.0.0.1:{p}"
                except Exception:
                    pass
    except Exception:
        pass
    # Launch the proxy in the background.
    try:
        subprocess.Popen(
            ["python3", "scripts/argo_ui_proxy.py", "--namespace", ns],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # Wait up to 5s for the proxy to write its port file and accept connections.
        t0 = time.time()
        while time.time() - t0 < 5:
            if os.path.exists(port_file):
                try:
                    with open(port_file, "r", encoding="utf-8") as f:
                        p = f.read().strip()
                    if p.isdigit():
                        with socket.create_connection(("127.0.0.1", int(p)), timeout=0.5):
                            return f"http://127.0.0.1:{p}"
                except Exception:
                    pass
            time.sleep(0.1)
    except Exception:
        pass
    return None


## No token minting or scheme probing here; the proxy handles auth and routing.


def _print_side_info():
    """Print the Argo UI URL served by the local auth-injecting proxy."""
    ns = os.environ.get("NAMESPACE", "argo")
    # Respect ARGO_UI_PROXY_URL if the proxy is already exposed by another process.
    proxy_url = os.environ.get("ARGO_UI_PROXY_URL")
    if proxy_url:
        print("🔗 Argo UI (via local HTTP proxy):")
        print(f"   {proxy_url}")
        print("   Auth is handled by the proxy.")
        return

    # Start or reuse the proxy and print its URL.
    proxy = _start_auth_proxy_bg(ns)
    print("🔗 Argo UI (via local HTTP proxy):")
    if proxy:
        print(f"   {proxy}")
        print("   Auth is handled by the proxy.")
        return

    # Fallback: print a URL from the existing port file, if present.
    try:
        portfile = os.path.join(os.getcwd(), ".work", "argo_ui_proxy.port")
        if os.path.exists(portfile):
            with open(portfile, "r", encoding="utf-8") as f:
                p = f.read().strip()
            if p.isdigit():
                url = f"http://127.0.0.1:{p}"
                print(f"   {url}")
                print("   Auth is handled by the proxy.")
                return
    except Exception:
        pass

    # Last resort: give a short, actionable hint.
    print("   (Proxy did not start. Ensure the cluster is up, then run: make ui-open)")


# The local proxy runs in the background and is reused across runs.

_printed_side = False


def _ensure_side_once():
    global _printed_side
    if not _printed_side:
        _print_side_info()
        _printed_side = True


print("🚀 Data-centric progress (quiet): updates only on change\n", flush=True)
_ensure_side_once()

for raw in sys.stdin:
    line = raw.rstrip("\n")
    m = pat_input.search(line)
    if m:
        state["input"] = m.group("url")
    m = pat_group.search(line) or pat_group2.search(line)
    if m:
        state["groups"].append(m.group("grp"))
    m = pat_band.search(line)
    if m:
        state["bands"].add((m.group("band") or m.group("band2")).strip())
    m = pat_overv_ok.search(line)
    if m:
        state["overviews"].add(m.group("lvl"))
    m = pat_output.search(line)
    if m:
        state["output"] = m.group("path")
    if pat_error.search(line):
        state["errors"] += 1
    # Capture specific error messages for a concise summary
    m = pat_convert_err.search(line)
    if m:
        state["last_error"] = m.group("msg")
    m = pat_argo_rpc.search(line)
    if m:
        code = m.group("code")
        desc = m.group("desc")
        state["last_error"] = f"Argo RPC {code}: {desc}"
    elif "Server disconnected" in line or "connection reset" in line.lower():
        state["last_error"] = "Server disconnected (transient network error)"
    elif pat_http_err.search(line) and ("status=" in line or "HTTP" in line):
        state["last_error"] = line.strip()
    if pat_done.search(line):
        state["done"] = True
    render()

render()
