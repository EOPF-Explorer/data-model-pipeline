#!/usr/bin/env python3
"""
Detect likely measurement groups in a Zarr store by scanning for resolution
group names (e.g., r10m/r20m/r60m) anywhere in the hierarchy.

Prints a space-separated list of matching group paths (with leading '/').
Returns empty output if none found or on error.
"""
from __future__ import annotations

import re
import sys
from typing import List


def main() -> int:
    if len(sys.argv) < 2:
        return 0
    store = sys.argv[1]

    try:
        import fsspec  # type: ignore
        import zarr  # type: ignore
    except Exception:
        # Dependencies not available; best-effort no-op
        return 0

    try:
        mapper = fsspec.get_mapper(store)
        root = zarr.open_group(mapper, mode="r")
    except Exception:
        # Can't open store; no-op
        return 0

    paths: List[str] = []

    def walk(g, prefix: str = "") -> None:
        # Iterate over mapping-like group children
        try:
            items = list(g.items())  # (name, node)
        except Exception:
            items = []
        for name, node in items:
            p = f"{prefix}/{name}" if prefix else f"/{name}"
            # Heuristic: recurse into subgroups; zarr Group has .group_keys or node.attrs may exist
            is_group = False
            try:
                # Newer zarr: Group type
                from zarr.hierarchy import Group as ZGroup  # type: ignore

                is_group = isinstance(node, ZGroup)
            except Exception:
                # Fallback heuristic: node has .items() means it's group-like
                is_group = hasattr(node, "items")
            if is_group:
                paths.append(p)
                walk(node, p)

    walk(root, "")

    rx = re.compile(r"/r\d+m$")
    selected = [p for p in paths if rx.search(p)]

    if selected:
        # Preserve traversal order, but de-duplicate
        seen = set()
        ordered = []
        for p in selected:
            if p not in seen:
                seen.add(p)
                ordered.append(p)
        sys.stdout.write(" ".join(ordered))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
