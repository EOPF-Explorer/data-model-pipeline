#!/usr/bin/env python3
# Non-repetitive progress UI: prints only when state changes.

import re, sys, hashlib

pat_input   = re.compile(r"Loading dataset from:\s*(?P<url>\S+)")
pat_group   = re.compile(r"Processing group(?:\s*for GeoZarr compliance)?:\s*(?P<grp>\S+)")
pat_group2  = re.compile(r"Processing\s+'?(?P<grp>/[^']+?)'? as GeoZarr group")
pat_band    = re.compile(r"Writing data variable\s+(?P<band>[^.]+)\.\.\.|Processing band:\s+(?P<band2>\S+)")
pat_overv_ok= re.compile(r"Level\s+(?P<lvl>\d+):\s+Successfully created")
pat_output  = re.compile(r"Output saved to:\s*(?P<path>\S+)")
pat_error   = re.compile(r"(Error during conversion|ERROR at line|Traceback)")
pat_done    = re.compile(r"(Successfully converted EOPF dataset to GeoZarr|Done\.)$")

state = {
    "input": None,
    "groups": [],
    "bands": set(),
    "overviews": set(),
    "output": None,
    "errors": 0,
    "done": False,
}
last_sig = None

def short(s, n=96): return (s[:n-1]+"…") if s and len(s)>n else s

def sig():
    g = tuple(state["groups"][-3:])
    b = tuple(sorted(list(state["bands"]))[-10:])
    o = tuple(sorted(int(x) for x in state["overviews"]))
    data = (state["input"], g, b, o, bool(state["output"]), state["errors"], state["done"])
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
    if state["done"]:
        lines.append("✅ Conversion complete.")
    print("\n".join(lines), flush=True)

print("🚀 Data-centric progress (quiet): updates only on change\n", flush=True)

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
    if pat_done.search(line):
        state["done"] = True
    render()

render()
