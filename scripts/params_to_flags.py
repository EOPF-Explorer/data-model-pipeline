#!/usr/bin/env python3
"""
Read an Argo parameters JSON file and emit '-p name=value' flags for non-empty values.

Usage:
    python3 scripts/params_to_flags.py params.json

Notes:
    - Supports either top-level {"parameters": [...]} or {"arguments": {"parameters": [...]}}
    - Skips empty values so template defaults apply and downstream CLIs don’t see empty strings.
"""
import json
import sys
import shlex


def main(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    params = []
    # Support both plain and nested structures
    param_list = []
    if isinstance(data, dict):
        if "arguments" in data and isinstance(data["arguments"], dict):
            param_list = data["arguments"].get("parameters", [])
        elif "parameters" in data:
            param_list = data["parameters"]
    # Emit flags only for non-empty values so Argo doesn't get -p name='' which can confuse downstream CLIs.
    for p in param_list:
        name = p.get("name")
        val = p.get("value", "")
        if name is None:
            continue
        sval = str(val) if val is not None else ""
        # Skip empty values to avoid passing literal "''" to Argo (use template defaults)
        if sval.strip() == "":
            continue
        # shell-quote non-empty values defensively
        params.append(f"-p {name}={shlex.quote(sval)}")
    print(" ".join(params))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("")
    else:
        main(sys.argv[1])
