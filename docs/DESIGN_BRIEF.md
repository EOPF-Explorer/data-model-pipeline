# LLM_BRIEF.md — data-model-pipeline (Argo → GeoZarr)

**Goal:** Convert **STAC Zarr** → **GeoZarr** using `eopf-geozarr` (from `EOPF-Explorer/data-model`) orchestrated by **Argo Workflows**. This brief gives constraints and context to optimize the repo without breaking behavior.

## Must-keep invariants
- CLI: `eopf-geozarr convert <input_path> <output_path> --groups <g1 g2 ...>` (positional input/output).
- Remote-first, wrapper-less: the WorkflowTemplate invokes `eopf-geozarr convert` directly. Groups are normalized in the template; validation is optional via `validate_groups`.
- WorkflowTemplate mounts a PVC at `/data`; `output_zarr` must live there.
- Local image imported into k3d; `imagePullPolicy: IfNotPresent`.
- Single `params.json`).

## External interfaces
**Workflow parameters**: `image`, `pvc_name`, `stac_url`, `output_zarr`, `groups`, `validate_groups` (bool-like).  
**Wrapper flags**: `--stac-url`, `--output-zarr`, `--groups`, `--validate-groups [true|false]`.

## Repo structure (authoritative pieces)
- `docker/Dockerfile`: multi-stage; wheels-first; fallback to install GDAL/PROJ; ensure `scripts/*.sh` are executable.
- `workflows/geozarr-convert-template.yaml`: minimal, correct, `command: [bash, -lc]`, passes flags, sets `PYTHONUNBUFFERED` and `VALIDATE_GROUPS` envs, mounts PVC.
- Wrapper removed; rely on direct CLI.
- `params.json`: sole defaults file.
- `Makefile`: `build`, `load-k3d`, `argo-install`, `template`, `submit`, `logs`, `status`, `pod`, `events`, `doctor`, `cluster-gc`.

## Caveats
- k3d nodes may have **DiskPressure**; controller won’t schedule. Use `cluster-gc` to prune `containerd` in node containers.
- Some object stores disallow directory listing; preflight warns and continues unless `VALIDATE_GROUPS=true`.
- GDAL/rasterio wheels may be missing; Dockerfile falls back to system GDAL/PROJ and re-runs pip.

## Optimization targets (safe to change)
- **Deps provenance**: sync 3rd-party deps from `data-model` lock (e.g., `uv.lock`) then `pip install --no-deps eopf-geozarr` from same ref.
- **Image**: slim layers, multi-arch, consistent Python ABI for rasterio wheels.
- **Argo**: resource requests/limits; per-group fan-out; optional tar artifact step.
- **DX**: stronger `make doctor` (ns, CRD, controller, DiskPressure checks).
- **CI**: build & smoke test in kind/k3d; push to GHCR.
- **Secrets**: credential flow for private object stores (fsspec envs/secret volumes).
- **Observability**: structured logs/metrics; OTEL hooks.

## Anti-goals
- Reintroducing dev-only knobs (`dask_perf_html`) into the template.
- Changing positional CLI to long flags for input/output.
- Moving outputs outside `/data` in the container.

# Design brief (archived)

This file summarized historical constraints for refactors.

Current behavior and parameters are documented in README and docs/.