#!/usr/bin/env python3
"""
Start or reuse the local Argo UI HTTP proxy and print its URL. Optionally open it.

This uses a small local proxy that injects Authorization for the Argo UI,
so you can use a plain http://127.0.0.1:<port> link without manual tokens.
"""

import argparse
import os
import socket
import subprocess
import time
import webbrowser


def _start_auth_proxy_bg(ns: str) -> str | None:
    """Start or reuse the local Argo UI HTTP proxy and return its URL."""
    work = os.path.join(os.getcwd(), ".work")
    os.makedirs(work, exist_ok=True)
    port_file = os.path.join(work, "argo_ui_proxy.port")
    # Reuse if already running
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
    # Start proxy
    try:
        subprocess.Popen(
            ["python3", "scripts/argo_ui_proxy.py", "--namespace", ns],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # Wait briefly for port file
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


def main():
    ap = argparse.ArgumentParser(description="Start/reuse local Argo UI proxy and print its URL.")
    ap.add_argument("--namespace", "-n", default=os.environ.get("NAMESPACE", "argo"), help="Kubernetes namespace")
    ap.add_argument("--open", action="store_true", help="Open the URL in your default browser")
    a = ap.parse_args()
    ns = a.namespace

    # Respect an externally provided proxy URL if set.
    url = os.environ.get("ARGO_UI_PROXY_URL")
    if not url:
        url = _start_auth_proxy_bg(ns)

    print("Argo UI (via local HTTP proxy):")
    if url:
        print(f"  {url}")
        if a.open:
            try:
                webbrowser.open(url)
            except Exception:
                try:
                    subprocess.run(["open", url], check=False)
                except Exception:
                    pass
    else:
        print("  (Proxy did not start. Ensure the cluster is up, then run: make ui-open)")


if __name__ == "__main__":
    main()
