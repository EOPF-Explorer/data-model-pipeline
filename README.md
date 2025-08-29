# Data Model Pipeline → GeoZarr (Argo prototype)

Convert Sentinel Zarr (from STAC) into **[GeoZarr](https://geozarr.readthedocs.io/)** using **Argo Workflows**.
This repo is a **local prototype**: it demonstrates the EOPF conversion flow end‑to‑end on a lightweight **k3d** cluster.

---

## Quickstart

```bash
# full local run (bootstrap → cluster → argo → build → import → pvc → template → submit)
make up

# if your cluster is already up (fast path):
make up-fast

# follow logs
make logs
```

---

## Prerequisites

- **Docker** (or compatible runtime)
- **k3d** (k3s in Docker): https://k3d.io/
- **kubectl**: https://kubernetes.io/docs/tasks/tools/
- **Argo Workflows CLI**: https://argo-workflows.readthedocs.io/en/stable/cli/
- **make**

You can quickly verify tool versions:

```bash
make doctor
```

---

## How it works

The pipeline wraps the `eopf-geozarr` CLI and runs it in a container via an Argo **WorkflowTemplate**.
Key files:
- `docker/Dockerfile` – builds a runnable image with `eopf-geozarr`.
- `workflows/geozarr-convert-template.yaml` – WorkflowTemplate used for submissions.
- `scripts/convert.sh` – robust wrapper: parses flags, normalizes group paths, preflights `.zgroup`, and validates groups (optional).
- `params.json` – default parameter values for local runs.
- `Makefile` – repeatable developer flow (cluster, install argo, build image, submit, logs, fetch results).

---

## Usage

### 1) Configure parameters (optional)

Edit `params.json` if you want to override defaults:

```json
{
  "arguments": {
    "parameters": [
      {"name": "stac_url",       "value": "https://…/S2…/my-scene.zarr"},
      {"name": "output_zarr",    "value": "/data/S2_scene_geozarr.zarr"},
      {"name": "groups",         "value": "measurements/reflectance/r20m"},
      {"name": "validate_groups","value": "false"}
    ]
  }
}
```

Notes:
- `output_zarr` must live under the mounted PVC path (`/data`).
- `groups` accepts one or many group paths; the wrapper can also read `$GROUPS`/`$ARGO_GROUPS`.
- If `validate_groups=true`, the run fails if a requested group is missing; otherwise a best‑effort suffix match is attempted with warnings.

### 2) Run

```bash
make up          # first time (cluster + argo + build + submit)
make up-fast     # subsequent runs (build + import + submit)
make logs        # follow the most recent workflow logs
```

### 3) Retrieve results

```bash
make fetch     # copies /data from the latest pod into ./out
```

---

## Limitations (prototype)

- Focused on **Sentinel Zarr → GeoZarr** single‑scene conversion.
- Tested locally on **k3d**; not production‑hardened for multi‑node clusters.
- Image is imported into the local cluster (no registry push).
- Minimal validation beyond group presence/shape checks.

---

## Design docs

- **[Design brief](docs/DESIGN_BRIEF.md)** — constraints and non‑negotiables for the working prototype.
- **[Explainer](docs/DESIGN_EXPLAINER.md)** — deeper rationale and operational guidance.
- **GeoZarr**: [spec repository](https://github.com/zarr-developers/geozarr-spec), [docs](https://geozarr.readthedocs.io/).

---

## License

Licensed under the **Apache License, Version 2.0**. See [LICENSE](LICENSE).
