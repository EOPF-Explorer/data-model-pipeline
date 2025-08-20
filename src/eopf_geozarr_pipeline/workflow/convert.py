"""Convert a single item from input_href to output_href using the eopf_geozarr CLI."""
import shlex
import subprocess
from pathlib import Path
from typing import List, Optional


def convert_one(
    input_href: str,
    output_href: str,
    groups: List[str],
    spatial_chunk: int = 4096,
    min_dimension: int = 256,
    tile_width: int = 256,
    max_retries: int = 3,
    use_dask: bool = True,
    dask_mode: str = "threads",
    dask_workers: int = 4,
    dask_threads_per_worker: int = 1,
    dask_perf_html: Optional[str] = None,
) -> None:
    """Convert a single item from input_href to output_href."""
    cmd = [
        "python", "-m", "eopf_geozarr.cli", "convert",
        input_href, output_href,
        "--groups", *groups,
        "--spatial-chunk", str(spatial_chunk),
        "--min-dimension", str(min_dimension),
        "--tile-width", str(tile_width),
        "--max-retries", str(max_retries),
    ]
    if use_dask:
        cmd += [
            "--dask-cluster",
            "--dask-mode", dask_mode,
            "--dask-workers", str(dask_workers),
            "--dask-threads-per-worker", str(dask_threads_per_worker),
        ]
        if dask_perf_html:
            Path(dask_perf_html).parent.mkdir(parents=True, exist_ok=True)
            cmd += ["--dask-perf-html", dask_perf_html]

    print("Running:", " ".join(shlex.quote(c) for c in cmd), flush=True)
    Path(output_href).parent.mkdir(parents=True, exist_ok=True)
    p = subprocess.run(cmd)
    if p.returncode != 0:
        raise SystemExit(p.returncode)
