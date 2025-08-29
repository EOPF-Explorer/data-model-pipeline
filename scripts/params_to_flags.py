#!/usr/bin/env python3
import json, sys, shlex

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
    for p in param_list:
        name = p.get("name")
        val = p.get("value", "")
        if name is None:
            continue
        # shell-quote values defensively
        params.append(f"-p {name}={shlex.quote(str(val))}")
    print(" ".join(params))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("")
    else:
        main(sys.argv[1])
