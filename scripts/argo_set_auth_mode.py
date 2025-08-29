#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import os


def sh(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def patch_deploy(ns: str, mode: str) -> None:
    # Get the current deployment
    raw = sh(["kubectl", "-n", ns, "get", "deploy", "argo-server", "-o", "json"])
    dep = json.loads(raw)

    # Find argo-server container by name
    containers = dep.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
    if not containers:
        print("argo-server deployment has no containers?", file=sys.stderr)
        sys.exit(1)
    name = "argo-server"
    c = None
    for _c in containers:
        if _c.get("name") == name:
            c = _c
            break
    if c is None:
        # Fallback to first container
        c = containers[0]
        name = c.get("name", "argo-server")

    # Ensure command starts argo server; if the command is odd (e.g. ['server']), replace with ['argocli','server']
    cmd = (c.get("command") or [])[:]
    if cmd:
        if cmd[0].endswith("argo") and (len(cmd) == 1 or (len(cmd) > 1 and cmd[1] != "server")):
            cmd = [cmd[0], "server"] + cmd[1:]
        elif cmd == ["server"] or cmd == ["argo-server"]:
            cmd = ["argocli", "server"]

    # Build args: remove existing --auth-mode (both '--auth-mode foo' and '--auth-mode=foo'),
    # and remove existing --secure flags (both forms). We'll re-add below as needed.
    args = (c.get("args", []) or [])[:]
    new_args: list[str] = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--auth-mode":
            # skip this and its value if present
            i += 2 if i + 1 < len(args) else 1
            continue
        if a.startswith("--auth-mode="):
            i += 1
            continue
        if a == "--secure":
            i += 2 if i + 1 < len(args) else 1
            continue
        if a.startswith("--secure="):
            i += 1
            continue
        new_args.append(a)
        i += 1
    new_args.append(f"--auth-mode={mode}")

    # Optionally control TLS: ARGO_SET_SECURE can be 'true'/'false'. If unset, leave as-is.
    set_secure = os.environ.get("ARGO_SET_SECURE")
    if set_secure is not None:
        set_secure_val = str(set_secure).lower() in ("1", "true", "yes")
        new_args.append(f"--secure={'true' if set_secure_val else 'false'}")

    # Compose env: ensure ARGO_SERVER_AUTH_MODE is set
    env = c.get("env", []) or []
    env = [e for e in env if e.get("name") != "ARGO_SERVER_AUTH_MODE"]
    env.append({"name": "ARGO_SERVER_AUTH_MODE", "value": mode})

    # Prepare strategic merge patch targeting the container by name to avoid dropping sidecars
    container_patch = {"name": name}
    if cmd:
        container_patch["command"] = cmd
    container_patch["args"] = new_args
    container_patch["env"] = env

    patched = json.dumps({"spec": {"template": {"spec": {"containers": [container_patch]}}}})
    sh(["kubectl", "-n", ns, "patch", "deploy", "argo-server", "--type=strategic", "-p", patched])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--namespace", "-n", default="argo")
    ap.add_argument("--mode", choices=["server", "client", "sso"], required=True)
    a = ap.parse_args()
    patch_deploy(a.namespace, a.mode)
    print(f"Patched argo-server to --auth-mode={a.mode} in namespace {a.namespace}")
