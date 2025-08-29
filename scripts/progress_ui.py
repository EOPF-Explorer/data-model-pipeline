#!/usr/bin/env python3
# Non-repetitive progress UI with side-panel Argo UI info.

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
    return (s[: n - 1] + "…") if s and len(s) > n else s


def sig():
    g = tuple(state["groups"][-3:])
    b = tuple(sorted(list(state["bands"]))[-10:])
    o = tuple(sorted(int(x) for x in state["overviews"]))
    data = (state["input"], g, b, o, bool(state["output"]), state["errors"], state["done"], state.get("last_error"))
    return hashlib.md5(repr(data).encode()).hexdigest()


def render():
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


def _find_free_port(preferred: int) -> int:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if s.connect_ex(("127.0.0.1", preferred)) != 0:
                return preferred
    except Exception:
        pass
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _pf_files():
    work = os.path.join(os.getcwd(), ".work")
    return work, os.path.join(work, "argo_pf.port"), os.path.join(work, "argo_pf.pid")


def _k8s_proxy_files():
    work = os.path.join(os.getcwd(), ".work")
    return work, os.path.join(work, "kubectl_proxy.port"), os.path.join(work, "kubectl_proxy.pid")


def _start_port_forward_bg(ns: str, target_port: int = 2746) -> int:
    work, port_file, pid_file = _pf_files()
    os.makedirs(work, exist_ok=True)
    # Reuse existing if alive
    try:
        if os.path.exists(port_file) and os.path.exists(pid_file):
            with open(port_file, "r", encoding="utf-8") as f:
                lp = int(f.read().strip())
            with open(pid_file, "r", encoding="utf-8") as f:
                pid = int(f.read().strip())
            # Check if process alive and port accepting
            if pid > 0:
                try:
                    os.kill(pid, 0)
                    with socket.create_connection(("127.0.0.1", lp), timeout=0.2):
                        return lp
                except Exception:
                    pass
    except Exception:
        pass
    # Start a new background port-forward
    local_port = int(os.environ.get("ARGO_UI_PORT", "2746"))
    local_port = _find_free_port(local_port)
    cmd = [
        "kubectl",
        "-n",
        ns,
        "port-forward",
        "svc/argo-server",
        f"{local_port}:{target_port}",
    ]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True)
        # Wait briefly for readiness
        t0 = time.time()
        ready = False
        while time.time() - t0 < 5:
            if proc.poll() is not None:
                break
            try:
                with socket.create_connection(("127.0.0.1", local_port), timeout=0.2):
                    ready = True
                    break
            except Exception:
                time.sleep(0.1)
        if ready:
            with open(port_file, "w", encoding="utf-8") as f:
                f.write(str(local_port))
            with open(pid_file, "w", encoding="utf-8") as f:
                f.write(str(proc.pid))
        return local_port
    except Exception:
        return local_port


def _get_bearer_token(ns: str):
    # Prefer Kubernetes SA token (works without argo cli context)
    try:
        out = subprocess.check_output(
            ["kubectl", "-n", ns, "create", "token", "argo-ui-dev", "--duration=1h"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            return out
    except Exception:
        # fallback to argo-server SA
        try:
            out = subprocess.check_output(
                ["kubectl", "-n", ns, "create", "token", "argo-server", "--duration=1h"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if out:
                return out
        except Exception:
            pass
    # Fallback to `argo auth token`
    try:
        out = subprocess.check_output(
            ["argo", "auth", "token", "-n", ns],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            return out
    except Exception:
        pass
    return None


def _probe_scheme(host: str, port: int, token: str) -> str:
    # Try HTTP first, then HTTPS (skip cert verify)
    try:
        subprocess.run(
            [
                "curl",
                "-sSfk",
                "-H",
                f"Authorization: Bearer {token}",
                f"http://{host}:{port}/api/v1/info",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return "http"
    except Exception:
        pass
    try:
        subprocess.run(
            [
                "curl",
                "-sSfk",
                "-H",
                f"Authorization: Bearer {token}",
                f"https://{host}:{port}/api/v1/info",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return "https"
    except Exception:
        pass
    # Fall back to env or http
    return os.environ.get("ARGO_UI_SCHEME", "http")


def _print_side_info():
    ns = os.environ.get("NAMESPACE", "argo")
    # If user provides a local HTTP proxy URL explicitly, prefer it and stop.
    proxy_url = os.environ.get("ARGO_UI_PROXY_URL")
    if proxy_url:
        print("🔗 Argo UI (via local HTTP proxy):")
        print(f"   {proxy_url}")
        print("   Auth is handled by the proxy. No token shown.")
        return
    # Provide official port-forward link only (no tokens shown by default)
    host = os.environ.get("ARGO_UI_HOST", "127.0.0.1")
    target_port = 2746
    try:
        p = subprocess.check_output(
            [
                "kubectl",
                "-n",
                ns,
                "get",
                "svc",
                "argo-server",
                "-o",
                "jsonpath={.spec.ports[0].port}",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if p:
            target_port = int(p)
    except Exception:
        pass

    local_port = _start_port_forward_bg(ns, target_port)
    token = _get_bearer_token(ns)
    # Determine http/https by probing /api/v1/info. Prefer http when --secure=false is set on server.
    scheme = _probe_scheme(host, local_port, token or "")
    url = f"{scheme}://{host}:{local_port}"
    print("🔗 Argo UI (official port-forward):")
    print(f"   {url}")
    # Only show token links if explicitly requested
    if os.environ.get("ARGO_SHOW_TOKEN_LINKS", "0").lower() in ("1", "true", "yes") and token:
        print("   Link with token:")
        print(f"     {url}/auth/token?token={token}")
        print(f"     {url}/?token={token}")
        print(f"     {url}/#/?token={token}")

    # Also print optional API proxy URL if a kubectl proxy is detected (we no longer auto-start it)
    if os.environ.get("ARGO_SHOW_ALT_LINKS", "0").lower() in ("1", "true", "yes"):
        try:
            kportfile = os.path.join(os.getcwd(), ".work", "kubectl_proxy.port")
            if os.path.exists(kportfile):
                with open(kportfile, "r", encoding="utf-8") as f:
                    kp = f.read().strip()
                if kp.isdigit():
                    print(
                        "   Alt (API proxy): http://127.0.0.1:",
                        kp,
                        f"/api/v1/namespaces/{ns}/services/https:argo-server:web/proxy/",
                        sep="",
                    )
        except Exception:
            pass

    # Prefer local HTTP auth-injecting proxy if running
    try:
        portfile = os.path.join(os.getcwd(), ".work", "argo_ui_proxy.port")
        if os.path.exists(portfile):
            with open(portfile, "r", encoding="utf-8") as f:
                p = f.read().strip()
            if p.isdigit():
                url = f"http://127.0.0.1:{p}"
                print("🔗 Argo UI (via local HTTP proxy):")
                print(f"   {url}")
                print("   Auth is handled by the proxy.")
                return
    except Exception:
        pass

    # Fallback (kept for completeness; official flow above already printed):
    ns = os.environ.get("NAMESPACE", "argo")
    host = os.environ.get("ARGO_UI_HOST", "127.0.0.1")
    scheme = "https"
    url = f"{scheme}://{host}:{local_port}"
    print("🔗 Argo UI:")
    print(f"   {url}")


# We leave the port-forward running in background for a stable URL; provide a Make target to stop it.

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
