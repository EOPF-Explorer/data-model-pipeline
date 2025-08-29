#!/usr/bin/env python3
import argparse, sys
p = argparse.ArgumentParser()
p.add_argument("--groups", required=True)
p.add_argument("-q", "--quiet", action="store_true")
a = p.parse_args()
ok = a.groups and a.groups.strip() and "/" in a.groups
if not ok:
    if not a.quiet:
        print(f"Invalid groups value: {a.groups!r}", file=sys.stderr)
    sys.exit(1)
