# Alignment plan: data-model-pipeline ↔ sentinel-zarr-explorer-coordination

Purpose: propose pragmatic steps to align pipeline execution, interfaces, and deliverables across both repositories so we can scale reliably on OVH Kubernetes and keep the explorer stack in sync.

## Shared objectives
- Consistent, spec-compliant GeoZarr outputs (Zarr v3) with predictable layout and metadata.
- Orchestrated, parallel processing with clear resource controls and observability.
- Simple, contract-first interfaces between workflow steps and downstream explorer/indexing services.
- CI/CD that ships container images and manifests to OVH with minimal manual steps.

## Architecture alignment
- Orchestration/DAG
  - Adopt fan-out per group/band/tile with Argo Workflows. Control parallelism at workflow and controller levels; define CPU/memory per template.
  - Reference (explorer repo): ADR-001 (pipeline orchestration) and ADR-002 (distributed scaling) for patterns and limits.
- Storage model
  - Scratch: RWO PVC (OVH Block Storage) for temp and local fan-out.
  - Outputs: write final artifacts directly to object storage (Swift/S3 API). Keep PVC use minimal to avoid IO bottlenecks.
  - Define a shared path convention, e.g.: s3://<bucket>/<collection>/<item_id>/<variant>/geozarr.zarr
- Data format & metadata
  - Align to GEOZARR spec and the “spec compliance” analysis in explorer repo (ADR-101 and GEOZARR_SPEC_COMPLIANCE_SUMMARY.md).
  - Add optional STAC Item/Collection sidecars for indexing into the explorer.

## Interface contracts (minimum viable)
- Parameters
  - Use data-model-pipeline `params.json` as the single source of truth; mirror its schema in the explorer API parameter design (ADR-202).
  - Scripts: keep `scripts/params_to_flags.py` authoritative for CLI/container flags; publish a JSON Schema to validate CI and API inputs.
- Inputs/outputs
  - Inputs: object store URIs or PVC mount paths; explicit band/group selection; temporal/spatial AOI.
  - Outputs: GeoZarr v3 with the agreed layout; optional STAC JSON; emit a small “run.json” manifest (URIs, checksums, timings) for the explorer indexer.
- Error and status
  - Standardize step exit codes and progress events; reuse `scripts/progress_ui.py` format for Argo annotations/logging.

## Operational alignment on OVH
- Images & registry
  - Build multi-arch images; tag with commit SHA and semver; push to an OVH-accessible registry. Use `imagePullSecrets` where required.
- RBAC & networking
  - Minimal ServiceAccount per workflow; scoped RBAC. Restrict egress to object store endpoints if needed.
- Observability
  - Argo UI + logs shipped to a common sink (e.g., Loki/Elastic). Include per-step resource requests/limits and retries.

## CI/CD (cross-repo)
- data-model-pipeline
  - Build and push images on PR/main; run lint/tests; publish `rendered.yaml` for reference; allow `kubectl diff && kubectl apply` to staging.
- explorer-coordination
  - Validate parameter compatibility (schema check) against data-model `params.json`.
  - Trigger indexing smoke tests on new GeoZarr outputs.
- Shared
  - A small conformance job: launch a minimal DAG on OVH that produces a GeoZarr sample and validates spec + STAC.

## Milestones
- M0 (1–2 days)
  - Finalize shared parameter names/types; publish JSON Schema; document path layout for object store outputs.
- M1 (1 week)
  - Run the current geozarr-convert workflow on OVH with fan-out; capture throughput; fix any PVC/object-store gaps.
- M2 (1–2 weeks)
  - Produce STAC sidecars and run an indexing job in explorer; validate end-to-end discoverability.
- M3 (continuous)
  - Harden RBAC/egress; add performance dashboards; tune parallelism at controller level.

## Risks & dependencies
- OVH object store performance/quota and network egress limits.
- Registry access and image size (cold-start times).
- Argo/K8s version skew; CSI driver behavior for PVCs.

## Pointers (explorer repo)
- ADR-001: data pipeline orchestration architecture
- ADR-002: distributed processing scaling strategy
- ADR-003: cloud infrastructure deployment architecture
- ADR-101: geozarr specification implementation approach
- ADR-201: titiler service architecture design
- ADR-202: web API parameter design

## Next actions
- Add a JSON Schema for `params.json` and validate in both repos’ CI.
- Prototype object store output writer; keep PVC only for scratch.
- Define a run manifest (run.json) and index it in the explorer pipeline.
