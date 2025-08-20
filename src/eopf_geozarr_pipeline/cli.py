# eopf_geozarr_pipeline/src/eopf_geozarr_pipeline/cli.py
import argparse
from pathlib import Path
from typing import List

from .workflow.convert import convert_one
from .workflow.discovery import discover_items, pick_input_href
from .workflow.register import (
    add_geozarr_asset,
    dict_to_item,
    ensure_catalog,
    ensure_collection,
    save_catalog,
)


def _add_run_parser(subparsers):
    p = subparsers.add_parser("run", help="Discover → Convert → Register")
    p.add_argument("--source-stac", required=True, help="STAC API URL (source)")
    p.add_argument("--source-collections", nargs="+", required=True, help="Source collection(s)")
    p.add_argument("--max-items", type=int, default=5)
    p.add_argument("--output-root", default="./out-zarr", help="Local dir or s3://… for outputs")
    p.add_argument("--target-stac-dir", default="./target-stac", help="Local static STAC directory")
    p.add_argument("--target-collection", default="geozarr-outputs")
    p.add_argument("--groups", nargs="+", default=["/measurements/r10m", "/measurements/r20m", "/measurements/r60m"])
    p.add_argument("--no-dask", action="store_true")
    p.add_argument("--dask-mode", default="threads", choices=["threads", "processes", "single-threaded"])
    p.add_argument("--dask-workers", type=int, default=4)
    p.add_argument("--dask-threads-per-worker", type=int, default=1)
    p.add_argument("--dask-perf-html-root", type=str, help="If set, write per-item report HTMLs under this dir")
    p.set_defaults(func=cmd_run)

def cmd_run(args: argparse.Namespace) -> None:
    """Run the discovery, conversion, and registration pipeline."""
    items = discover_items(args.source_stac, args.source_collections, args.max_items)
    if not items:
        print("No items discovered.")
        return

    target_root = Path(args.target_stac_dir)
    cat = ensure_catalog(target_root)
    coll = ensure_collection(cat, args.target_collection)

    for src in items:
        item_id = src["id"]
        collection = src.get("collection") or "unknown"
        href_in = pick_input_href(src)
        if not href_in:
            print(f"[skip] {item_id}: no usable input asset found")
            continue

        out_dir = Path(args.output_root) / collection
        out_dir.mkdir(parents=True, exist_ok=True)
        href_out = str(out_dir / f"{item_id}.zarr")
        perf_html = None
        if args.dask_perf_html_root:
            perf_html = str(Path(args.dask_perf_html_root) / f"{item_id}.html")

        print(f"\n[{item_id}] input={href_in}\n           output={href_out}")

        # Convert one item (shells out to eopf_geozarr CLI)
        convert_one(
            input_href=href_in,
            output_href=href_out,
            groups=args.groups,
            use_dask=(not args.no_dask),
            dask_mode=args.dask_mode,
            dask_workers=args.dask_workers,
            dask_threads_per_worker=args.dask_threads_per_worker,
            dask_perf_html=perf_html,
        )

        # Register in separate local STAC
        new_item = dict_to_item(src, args.target_collection)
        add_geozarr_asset(new_item, href_out)
        coll.add_item(new_item)
        save_catalog(cat, target_root)

    print("\nDone. Target STAC at:", target_root.resolve())

def main(argv: List[str] | None = None) -> None:
    """Entry point for the CLI."""
    ap = argparse.ArgumentParser(prog="eopf-geozarr-pipeline", description="Local EOPF → GeoZarr pipeline")
    sub = ap.add_subparsers(dest="command")
    _add_run_parser(sub)
    args = ap.parse_args(argv)
    if hasattr(args, "func"):
        args.func(args)
    else:
        ap.print_help()
