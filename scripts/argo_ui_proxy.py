#!/usr/bin/env python3
"""
Auth-injecting reverse proxy for Argo UI.

Runs a local HTTP server that:
- starts `kubectl port-forward` to svc/argo-server in the given namespace,
- obtains a bearer token (kubectl create token / argo auth token),
- forwards all requests to the argo-server via the port-forward,
- injects `Authorization: Bearer <token>` so the UI works without manual auth,
- ignores upstream self-signed TLS by default.

Usage:
  python3 scripts/argo_ui_proxy.py --namespace argo [--port 8081]

Then open the printed http://127.0.0.1:<port> URL.
Ctrl+C to stop (it cleans up the port-forward).
"""
from __future__ import annotations

import argparse
import atexit
import http.client
import os
import socket
import socketserver
import ssl
import subprocess
import sys
from http.server import BaseHTTPRequestHandler
from urllib.parse import urlsplit


def find_free_port(preferred: int | None = None) -> int:
    if preferred:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            if s.connect_ex(("127.0.0.1", preferred)) != 0:
                s.close()
                return preferred
        finally:
            try:
                s.close()
            except Exception:
                pass
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def get_token(ns: str) -> str | None:
    # Prefer kubectl minting a short-lived token
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
    # Fallback to Argo CLI
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


def get_upstream_port(ns: str) -> int:
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
            return int(p)
    except Exception:
        pass
    return 2746


def start_port_forward(ns: str, upstream_port: int) -> int:
    local_port = find_free_port(upstream_port)
    cmd = [
        "kubectl",
        "-n",
        ns,
        "port-forward",
        "svc/argo-server",
        f"{local_port}:{upstream_port}",
    ]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    # Basic readiness wait
    for _ in range(50):
        try:
            with socket.create_connection(("127.0.0.1", local_port), timeout=0.1):
                break
        except Exception:
            pass
    return local_port, proc


def probe_scheme(host: str, port: int, token: str | None) -> str:
    # Prefer HTTPS; some servers close on HEAD, so use GET
    try:
        ctx = ssl._create_unverified_context()  # nosec
        conn = http.client.HTTPSConnection(host, port, context=ctx, timeout=3)
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        conn.request("GET", "/api/v1/info", headers=headers)
        resp = conn.getresponse()
        resp.read()
        return "https"
    except Exception:
        pass
    # Fallback to HTTP
    try:
        conn = http.client.HTTPConnection(host, port, timeout=3)
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        conn.request("GET", "/api/v1/info", headers=headers)
        resp = conn.getresponse()
        resp.read()
        return "http"
    except Exception:
        pass
    # Default to https if uncertain
    return "https"


class ThreadingHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_ANY(self):  # type: ignore[override]
        server: ThreadingHTTPServer = self.server  # type: ignore[assignment]
        upstream_host: str = server.upstream_host  # type: ignore[attr-defined]
        upstream_port: int = server.upstream_port  # type: ignore[attr-defined]
        upstream_scheme: str = server.upstream_scheme  # type: ignore[attr-defined]
        token: str | None = server.bearer_token  # type: ignore[attr-defined]
        ns: str = server.ns  # type: ignore[attr-defined]
        upstream_svc_port: int = server.upstream_svc_port  # type: ignore[attr-defined]
        path_prefix: str | None = getattr(server, "upstream_path_prefix", None)  # type: ignore[attr-defined]
        inject_auth: bool = bool(getattr(server, "inject_auth", True))  # type: ignore[attr-defined]

        # Build headers and sanitize
        raw_headers = {k: v for k, v in self.headers.items()}

        def sanitize_headers(h: dict[str, str]) -> dict[str, str]:
            out: dict[str, str] = {}
            hop = {"connection", "proxy-connection", "keep-alive", "transfer-encoding", "upgrade", "te"}
            for k, v in h.items():
                lk = k.lower()
                # Drop hop-by-hop and sensitive/conflicting headers
                if lk in hop or lk == "cookie" or lk == "authorization" or lk == "content-length":
                    continue
                # Ensure value is printable ASCII (no CR/LF/tab)
                sv = str(v).replace("\r", "").replace("\n", "")
                sv = "".join(ch for ch in sv if 32 <= ord(ch) <= 126)
                out[k] = sv
            return out

        base_headers = sanitize_headers(raw_headers)
        base_headers["Host"] = f"127.0.0.1:{upstream_port}"
        base_headers["Connection"] = "close"
        if inject_auth and token:
            base_headers["Authorization"] = f"Bearer {token}"
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length > 0 else None

        def forward_once(scheme: str):
            if scheme == "https":
                ctx = ssl._create_unverified_context()  # nosec
                conn_ = http.client.HTTPSConnection(upstream_host, upstream_port, context=ctx, timeout=30)
            else:
                conn_ = http.client.HTTPConnection(upstream_host, upstream_port, timeout=30)
            path_ = f"{path_prefix}{self.path}" if path_prefix else self.path
            conn_.request(self.command, path_, body=body, headers=base_headers)
            return conn_.getresponse()

        def ensure_pf_alive():
            # Restart port-forward if dead or not connectable
            try:
                if getattr(server, "pf_proc", None) is None or server.pf_proc.poll() is not None:  # type: ignore[attr-defined]
                    # (Re)start
                    if getattr(server, "mode", "port-forward") == "port-forward":  # type: ignore[attr-defined]
                        new_port, new_proc = start_port_forward(ns, upstream_svc_port)
                        server.upstream_port = new_port  # type: ignore[attr-defined]
                        server.pf_proc = new_proc  # type: ignore[attr-defined]
                        server.upstream_scheme = probe_scheme("127.0.0.1", new_port, token)  # type: ignore[attr-defined]
                    else:
                        # k8s-proxy mode: ensure kubectl proxy is running; if not, start it
                        k8s_port = getattr(server, "k8s_proxy_port", 8001)  # type: ignore[attr-defined]
                        try:
                            with socket.create_connection(("127.0.0.1", k8s_port), timeout=0.2):
                                pass
                        except Exception:
                            proc = subprocess.Popen(["kubectl", "proxy", f"--port={k8s_port}"])
                            server.pf_proc = proc  # type: ignore[attr-defined]
                            try:
                                with socket.create_connection(("127.0.0.1", k8s_port), timeout=2):
                                    pass
                            except Exception:
                                pass
                        server.upstream_port = k8s_port  # type: ignore[attr-defined]
                        server.upstream_scheme = "http"  # type: ignore[attr-defined]
                else:
                    # Quick TCP check
                    with socket.create_connection(("127.0.0.1", server.upstream_port), timeout=0.2):  # type: ignore[attr-defined]
                        pass
            except Exception:
                # Hard restart on any error
                try:
                    if getattr(server, "pf_proc", None) and server.pf_proc.poll() is None:  # type: ignore[attr-defined]
                        server.pf_proc.terminate()  # type: ignore[attr-defined]
                except Exception:
                    pass
                if getattr(server, "mode", "port-forward") == "port-forward":  # type: ignore[attr-defined]
                    new_port, new_proc = start_port_forward(ns, upstream_svc_port)
                    server.upstream_port = new_port  # type: ignore[attr-defined]
                    server.pf_proc = new_proc  # type: ignore[attr-defined]
                    server.upstream_scheme = probe_scheme("127.0.0.1", new_port, token)  # type: ignore[attr-defined]
                else:
                    k8s_port = getattr(server, "k8s_proxy_port", 8001)  # type: ignore[attr-defined]
                    proc = subprocess.Popen(["kubectl", "proxy", f"--port={k8s_port}"])
                    server.pf_proc = proc  # type: ignore[attr-defined]
                    server.upstream_port = k8s_port  # type: ignore[attr-defined]
                    server.upstream_scheme = "http"  # type: ignore[attr-defined]

        # Built-in health/debug endpoints
        if self.path == "/_health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            info = {
                "ns": ns,
                "pf_port": upstream_port,
                "scheme": upstream_scheme,
                "has_token": bool(token),
                "path_prefix": path_prefix or "",
            }
            self.wfile.write((str(info)).encode())
            return
        if self.path == "/_debug":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(
                f"ns={ns}\nupstream_port={upstream_port}\nscheme={upstream_scheme}\npath_prefix={path_prefix}\n".encode()
            )
            return

        try:
            # Ensure upstream connectivity
            ensure_pf_alive()
            upstream_port = server.upstream_port  # type: ignore[attr-defined]
            upstream_scheme = server.upstream_scheme  # type: ignore[attr-defined]

            # Try sequence with retries: [current, flip], then restart and retry
            def attempt_sequences():
                schemes = [upstream_scheme, "http" if upstream_scheme == "https" else "https"]
                last_exc = None
                for sch in schemes:
                    try:
                        return forward_once(sch)
                    except Exception as e:
                        last_exc = e
                        continue
                ensure_pf_alive()
                schemes = [server.upstream_scheme, "http" if server.upstream_scheme == "https" else "https"]  # type: ignore[attr-defined]
                for sch in schemes:
                    try:
                        return forward_once(sch)
                    except Exception as e:
                        last_exc = e
                        continue
                raise last_exc if last_exc else RuntimeError("forward failed")

            resp = attempt_sequences()

            data = resp.read()

            # Copy response headers (exclude hop-by-hop)
            self.send_response(resp.status, resp.reason)
            hop = {
                "connection",
                "keep-alive",
                "proxy-authenticate",
                "proxy-authorization",
                "te",
                "trailers",
                "transfer-encoding",
                "upgrade",
            }
            for k, v in resp.getheaders():
                lk = k.lower()
                if lk in hop:
                    continue
                if lk == "location":
                    try:
                        u = urlsplit(v)
                        v = v.replace(f"{u.scheme}://{u.netloc}", f"http://{self.server.server_address[0]}:{self.server.server_address[1]}")  # type: ignore[attr-defined]
                    except Exception:
                        pass
                self.send_header(k, v)
            self.send_header("Connection", "close")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if data:
                self.wfile.write(data)
        except Exception as e:
            msg = f"Upstream error: {e}"
            self.send_response(502, "Bad Gateway")
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(msg)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(msg.encode())

    # Map common verbs
    def do_GET(self):
        self.do_ANY()

    def do_POST(self):
        self.do_ANY()

    def do_PUT(self):
        self.do_ANY()

    def do_DELETE(self):
        self.do_ANY()

    def log_message(self, fmt, *args):
        # Quiet unless verbose is enabled
        verbose = getattr(self.server, "verbose", False)
        if verbose:
            sys.stderr.write("[proxy] " + fmt % args + "\n")


def main():
    ap = argparse.ArgumentParser(description="Auth-injecting Argo UI proxy")
    ap.add_argument("--namespace", "-n", default=os.environ.get("NAMESPACE", "argo"))
    ap.add_argument("--port", type=int, default=None, help="Local HTTP port (default: auto)")
    ap.add_argument(
        "--mode",
        choices=["port-forward", "k8s-proxy"],
        default=os.environ.get("ARGO_UI_PROXY_MODE", "port-forward"),
        help="Upstream mode: connect via port-forward to svc/argo-server or via kubectl API server proxy",
    )
    ap.add_argument(
        "--k8s-proxy-port",
        type=int,
        default=int(os.environ.get("K8S_PROXY_PORT", "8001")),
        help="kubectl proxy port when mode=k8s-proxy",
    )
    ap.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    args = ap.parse_args()

    ns = args.namespace
    mode = args.mode
    if mode == "port-forward":
        upstream_port = get_upstream_port(ns)
        pf_port, pf_proc = start_port_forward(ns, upstream_port)
        atexit.register(lambda: pf_proc.terminate() if pf_proc and pf_proc.poll() is None else None)
        token = get_token(ns)
        scheme = probe_scheme("127.0.0.1", pf_port, token)
        upstream_path_prefix = None
        inject_auth = True
    else:
        # k8s-proxy mode: talk to local kubectl proxy and route to service proxy path; no auth injection needed
        upstream_port = args.k8s_proxy_port
        # ensure kubectl proxy is running
        try:
            with socket.create_connection(("127.0.0.1", upstream_port), timeout=0.5):
                pf_proc = None
        except Exception:
            pf_proc = subprocess.Popen(["kubectl", "proxy", f"--port={upstream_port}"])  # nosec
            atexit.register(lambda: pf_proc.terminate() if pf_proc and pf_proc.poll() is None else None)
        token = None
        scheme = "http"
        upstream_path_prefix = f"/api/v1/namespaces/{ns}/services/https:argo-server:web/proxy"
        inject_auth = False

    http_port = find_free_port(args.port)
    server = ThreadingHTTPServer(("127.0.0.1", http_port), ProxyHandler)
    # Attach upstream config to server object
    server.upstream_host = "127.0.0.1"  # type: ignore[attr-defined]
    server.upstream_port = pf_port if mode == "port-forward" else upstream_port  # type: ignore[attr-defined]
    server.upstream_scheme = scheme  # type: ignore[attr-defined]
    server.bearer_token = token  # type: ignore[attr-defined]
    server.ns = ns  # type: ignore[attr-defined]
    server.upstream_svc_port = upstream_port  # type: ignore[attr-defined]
    server.pf_proc = pf_proc if mode == "port-forward" else pf_proc  # type: ignore[attr-defined]
    server.mode = mode  # type: ignore[attr-defined]
    server.k8s_proxy_port = args.k8s_proxy_port  # type: ignore[attr-defined]
    server.upstream_path_prefix = upstream_path_prefix  # type: ignore[attr-defined]
    server.inject_auth = inject_auth  # type: ignore[attr-defined]
    server.verbose = args.verbose  # type: ignore[attr-defined]

    # Write port file for progress_ui discovery when started via Makefile
    try:
        workdir = os.path.join(os.getcwd(), ".work")
        os.makedirs(workdir, exist_ok=True)
        with open(os.path.join(workdir, "argo_ui_proxy.port"), "w", encoding="utf-8") as f:
            f.write(str(http_port))
    except Exception:
        pass

    print(f"Argo UI proxy ready at http://127.0.0.1:{http_port}")
    if args.verbose:
        if mode == "port-forward":
            print(f"  Upstream: {scheme}://127.0.0.1:{pf_port} (svc/argo-server in ns={ns}, svcPort={upstream_port})")
            if token:
                print("  Injecting Bearer token into all requests.")
            else:
                print("  Warning: no token available; UI calls may 401.")
        else:
            print(f"  Upstream: http://127.0.0.1:{upstream_port}{upstream_path_prefix} (via kubectl proxy)")
            print("  Cookie headers are stripped; no auth injection required.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        try:
            server.shutdown()
        except Exception:
            pass


if __name__ == "__main__":
    main()
