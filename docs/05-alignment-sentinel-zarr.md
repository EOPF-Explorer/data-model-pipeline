# Alignment: data-model-pipeline ↔ sentinel-zarr-explorer-coordination

Purpose: keep pipeline interfaces and outputs compatible across repos for OVH scale-out.

Shared objectives
- Spec-compliant GeoZarr outputs with predictable layout.
- Parallel orchestration with clear resource controls.
- Contract-first parameters and small, portable artifacts for indexing.

Architecture (see ADR-001/002/003 in coordination repo)
- Fan-out per group/band/tile; set workflow/controller parallelism; per-step resources.
- Scratch on PVC if needed; write final outputs to object storage (S3/Swift API).
- Shared path convention, e.g. `s3://<bucket>/<collection>/<item_id>/<variant>/geozarr.zarr`.

Interfaces
- Treat `params.json` as source of truth; mirror types in explorer API.
- Keep `scripts/params_to_flags.py` authoritative; publish a JSON Schema for CI.
- Outputs: GeoZarr v3 and optional STAC JSON; consider a tiny `run.json` manifest.

Ops on OVH (see ADR-003)
- Multi-arch images published to GHCR (ghcr.io/EOPF-Explorer/eopf-geozarr:TAG); configure imagePullSecrets where required by the cluster.
- Minimal RBAC; restrict egress to object storage endpoints.
- Logs visible in Argo UI and shipped to a common sink.

Next actions
- Publish JSON Schema for params; validate in CI (both repos).
- Run the current workflow on OVH with fan-out and measure throughput.
- Produce STAC sidecars and index a sample end-to-end.
