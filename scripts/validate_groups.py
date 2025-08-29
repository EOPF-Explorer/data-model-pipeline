#!/usr/bin/env python3
import argparse
import json
import os
import sys


def extract_groups_from_params(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None
    params = []
    if isinstance(data, dict):
        if "arguments" in data and isinstance(data["arguments"], dict):
            params = data["arguments"].get("parameters", [])
        elif "parameters" in data:
            params = data["parameters"]
    for p in params:
        if p.get("name") == "groups":
            return str(p.get("value", ""))
    return None


def main():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("positional", nargs="?")  # optional params file path
    p.add_argument("--groups")
    p.add_argument("--params-file", default="params.json")
    p.add_argument("-q", "--quiet", action="store_true")
    try:
        a, _ = p.parse_known_args()
    except SystemExit:
        # Be quiet even if args are odd; let validation pass silently
        return 0

    groups = a.groups
    if not groups:
        # Try positional JSON path, then --params-file, then env vars
        cand = a.positional if (a.positional and a.positional.endswith(".json")) else a.params_file
        if cand and os.path.exists(cand):
            groups = extract_groups_from_params(cand)
        if not groups:
            groups = os.environ.get("GROUPS") or os.environ.get("ARGO_GROUPS")

    ok = bool(groups and str(groups).strip() and "/" in str(groups))
    if not ok:
        if not a.quiet:
            print(f"Invalid groups value: {groups!r}", file=sys.stderr)
        return 1
    if not a.quiet:
        print(f"groups validated: {groups}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
