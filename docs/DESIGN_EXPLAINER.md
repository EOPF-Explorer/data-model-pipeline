
# data-model-pipeline — Explainer & Optimization Brief (for LLMs)

This repo is an **Argo-native orchestration layer** that converts **STAC Zarr** items into **GeoZarr** using the `eopf-geozarr` CLI from the upstream **data-model** repo (`EOPF-Explorer/data-model`). It supplies the **runner image**, the **Argo WorkflowTemplate**, a small **Bash wrapper** around the CLI, and **Make targets** for a smooth local-dev loop on **k3d/k3s**.

The goal of this document is to pass all *relevant operational context* and *design constraints* to another LLM so it can further **simplify**, **optimize**, and **harden** the pipeline **without breaking the working flow**.

---

## TL;DR — What must keep working

- **CLI contract** (from `data-model`):  
  `eopf-geozarr convert <input_path> <output_path> --groups <one or more group paths> [--dask-cluster] [--verbose]`  
  *Important:* `convert` expects **positional** `input` and `output`. Default groups in the CLI are `["/measurements/r10m", "/measurements/r20m", "/measurements/r60m"]`, but here we pass **explicit groups**.
- Remote-first: the workflow calls the `eopf-geozarr` CLI directly inside the container. Group paths are normalized in-template; optional validation can be enabled via the `validate_groups` parameter.
- **WorkflowTemplate**: minimal & valid Argo spec, **no dev-only params** (`dask_perf_html` removed), PVC mounted at `/data`, `imagePullPolicy: IfNotPresent`.
- **Image**: built locally and **imported into k3d**, so the pod doesn’t need to pull from registries.
- **Namespace**: everything targets **`argo`** (not `argo-workflows`). Argo version used in manifests/logs is **v3.6.5**.

---

## Repo Layout (essential files)

- `docker/Dockerfile` — builds the runner image:
  - Installs `eopf-geozarr` from the **data-model** repo via `pip install git+…`.
  - If `rasterio` fails to import, installs **GDAL/PROJ** system packages and retries pip install (wheels → source build fallback).
  - Ensures `scripts/*.sh` are **executable** after `COPY`.
- Wrapper removed: direct CLI usage in the Argo template keeps the surface minimal and avoids an extra layer.
  - accepts `--stac-url`, `--output-zarr`, `--groups …`
  - **normalizes** groups to absolute paths (`/…`), falls back to `$ARGO_GROUPS` if empty/`0`
  - **preflights** (via `fsspec`) to list `.zgroup`s and **validate** requested groups (prints *Available/Missing/Suggestions*)
  - calls: `eopf-geozarr convert "${STAC_URL}" "${OUTPUT_ZARR}" --groups "${NORM_GROUPS[@]}"`
- `workflows/geozarr-convert-template.yaml` — **clean** Argo WorkflowTemplate:
  - `entrypoint: geozarr-convert`, `serviceAccountName: default`
  - parameters: `image`, `pvc_name`, `stac_url`, `output_zarr`, `groups`, `validate_groups`
  - container runs `bash -lc` and invokes `eopf-geozarr convert …` directly
  - mounts PVC param at `/data` (used for `output_zarr`)
- `params.json` — the **only** param file; no `.example`:
  ```json
  {
    "arguments": {
      "parameters": [
        { "name": "stac_url", "value": "<S2 Zarr URL>" },
        { "name": "output_zarr", "value": "/data/<name>_geozarr.zarr" },
        { "name": "groups", "value": "measurements/reflectance/r20m" },
        { "name": "validate_groups", "value": "false" }
      ]
    }
  }
  ```
- `Makefile` — streamlined targets: `build`, `load-k3d`, `argo-install`, `template`, `submit`, `status`, `pod`, `events`, `logs`, `doctor`, and a **cluster GC** target for k3d disk pressure.

## Known-good quickstart

```bash
# Image
docker build -t eopf-geozarr:dev -f docker/Dockerfile .
k3d image import --cluster k3s-default eopf-geozarr:dev

# Argo (namespace argo, version v3.6.5)
kubectl create ns argo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.5/install.yaml

# If controller is Pending due to DiskPressure (k3d):
#   docker exec k3d-k3s-default-server-0 sh -lc 'crictl rmp -fa; crictl rmi --prune; ctr -n k8s.io images prune; ctr -n k8s.io content gc'
#   docker exec k3d-k3s-default-agent-0  sh -lc 'crictl rmp -fa; crictl rmi --prune; ctr -n k8s.io images prune; ctr -n k8s.io content gc'

kubectl -n argo rollout status deploy/workflow-controller

# Template
kubectl apply -n argo -f workflows/geozarr-convert-template.yaml

# Submit (edit values or use params.json via argo submit -f)
argo submit -n argo --from workflowtemplate/geozarr-convert   -p image=eopf-geozarr:dev   -p pvc_name=geozarr-pvc   -p stac_url="<S2 Zarr URL>"   -p output_zarr="/data/<name>_geozarr.zarr"   -p groups="measurements/reflectance/r20m"   -p validate_groups=false

# Observe
kubectl -n argo get pods
# Tail logs (main container)
#   kubectl -n argo logs -f <pod> -c main
```

**Artifacts**: the converted GeoZarr goes to the PVC at the `output_zarr` path. (If a tarball step is needed later, add a second step or post-command tar.)

---

## Troubleshooting playbook (copy/paste friendly)

### YAML / Template
- Parse error on apply → check quoting, or re-apply the **minimal** template in this repo.

### Workflow stuck `Pending` (no pod created)
```bash
kubectl get crd workflows.argoproj.io workflowtemplates.argoproj.io
kubectl -n argo get deploy,po -l app=workflow-controller
# If missing or not Running → reinstall v3.6.5 in ns=argo
```

### Controller pod `Pending`
```bash
kubectl -n argo describe rs $(kubectl -n argo get rs -l app=workflow-controller -o jsonpath='{.items[-1:].metadata.name}') | sed -n '/Events:/,$p'

# If DiskPressure:
docker exec k3d-k3s-default-server-0 sh -lc 'crictl rmp -fa; crictl rmi --prune; ctr -n k8s.io images prune; ctr -n k8s.io content gc'
docker exec k3d-k3s-default-agent-0  sh -lc 'crictl rmp -fa; crictl rmi --prune; ctr -n k8s.io images prune; ctr -n k8s.io content gc'
kubectl -n argo rollout restart deploy/workflow-controller
```

### Image pull issues (workflow pod)
- Import the exact tag into k3d: `k3d image import --cluster k3s-default eopf-geozarr:dev`
- Ensure the template uses `imagePullPolicy: IfNotPresent`.

### Exec permission denied (wrapper)
- Ensure the runtime image includes `/bin/bash` and `eopf-geozarr` on PATH.

### Group/path errors (`Could not find node at 0`)
- Use **absolute** group paths (leading `/`).  
- The wrapper will list available groups and **suggest** close matches.

---

## Design choices worth preserving

- **Separation of concerns**: converter lives in `data-model`; this repo is orchestration only.
- **No duplicate config**: single `params.json`, no `.example` file.
- **Validate early**: group preflight prevents opaque failures later.
- **Local-first images**: avoid registry pulls in inner dev loop.
- **Minimal Argo template**: fewer knobs ⇒ fewer YAML footguns.

---

## Optimization ideas (safe to pursue)

1. **Dependency alignment with `data-model`:**
   - Consume upstream lock (e.g., `uv.lock` or pinned constraints). Option A: `pip install -r` exported from upstream lock. Option B: `uv pip sync` for exact third-party deps, then `pip install --no-deps eopf-geozarr` from the same ref.
   - Ensure Python ABI matches wheels for GDAL stack (py310/py311).
2. **Image size & build speed:**
   - Multi-stage: keep GDAL/PROJ only in runtime if needed; test `manylinux` wheels first, avoid dev headers in final layer.
   - Consider `micromamba` for native libs where wheels lack coverage.
3. **Argo improvements:**
   - Add resource requests/limits; expose as params if needed.
   - Optional: second step to tar outputs to `/outputs/geozarr.tar.gz` as artifact.
   - Structured logs & more explicit failure messages.
4. **DX polish:**
   - `make doctor`: already present; extend with “controller ns mismatch” checks.
   - `make argo-install`: pin version (v3.6.5) and verify CRDs + controller pods.
   - Add `make cluster-gc` (k3d containerd GC) target by default.
5. **Tests & reproducibility:**
   - Small **golden** STAC Zarr + expected GeoZarr for a CI smoke.
   - `act`/`kind` or a light e2e workflow locally.
6. **Packaging:**
   - Optional Helm chart containing the WorkflowTemplate + PVC.
   - GHCR publishing of runner image on tags/commits.

---

## Guardrails for future edits (for LLMs)

- Do **not** reintroduce `dask_perf_html` in the template (dev-only).
- Do **not** change CLI invocation off positional args.
- Always **normalize** and **validate** group paths before convert.
- Keep `imagePullPolicy: IfNotPresent` and remember to **import** the image into k3d.
- Keep the **namespace** consistent (`argo`), or make it a Makefile param *and* update `kubectl`/`argo` calls accordingly.
- Preserve `params.json` as the single source of defaults.

---

## Handy snippets

**Makefile target for k3d node GC**:
```make
CLUSTER ?= k3s-default
cluster-gc:
	@SERVER=$$(docker ps --format '{{.Names}}' | grep "k3d-$(CLUSTER)-server-0"); \
	AGENT=$$(docker ps --format '{{.Names}}'  | grep "k3d-$(CLUSTER)-agent-0"); \
	for n in $$SERVER $$AGENT; do \	  [ -z "$$n" ] && continue; \	  echo "== $$n =="; \	  docker exec "$$n" sh -lc 'set -e; \	    crictl rmp -fa || true; crictl rmi --prune || true; \	    ctr -n k8s.io images prune || true; ctr -n k8s.io content gc || true; \	    df -h /'; \	done
```

**zsh-safe DiskPressure query**:
```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,DISK_PRESSURE:.status.conditions[?(@.type=="DiskPressure")].status'
```

**Describe newest controller ReplicaSet events**:
```bash
kubectl -n argo describe rs $(kubectl -n argo get rs -l app=workflow-controller -o jsonpath='{.items[-1:].metadata.name}') | sed -n '/Events:/,$p'
```

---

## Final checklist for running

- [ ] Argo CRDs exist & controller is **Running** in `argo` (v3.6.5).
- [ ] Node **DiskPressure** is `False` on at least one node.
- [ ] Runner image built & **imported** into k3d.
- [ ] Template applied; `params.json` uses `/data/...` for outputs.
- [ ] Submit with **absolute** group paths (or rely on wrapper normalization).
- [ ] Use `make logs` or `kubectl logs -f <pod> -c main` to observe.

---

**Contact surface for the next LLM**  
If you’re optimizing this further, start by:
1) Reducing Docker image size while preserving GDAL/rasterio ergonomics.  
2) Turning preflight into a tiny Python entrypoint (cleaner logging, unit tests).  
3) Folding controller/bootstrap checks into `make doctor` with clear remedies.  

