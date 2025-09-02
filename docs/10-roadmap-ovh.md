# Roadmap to OVH (next steps)

**Goal**: run the same Argo templates on an OVH-hosted Kubernetes cluster and scale out.

## Storage
- Start with OVH Block Storage (RWO PVC) to mirror local behavior.
- Object store outputs (S3 API) are already supported via the `upload-s3` task; the PVC is used for scratch and conversion output before upload.

## Scaling
- Increase throughput by fan-out per *group/band/tile*. Use a DAG with parallel steps.
- Control parallelism at **workflow** and **controller** levels; set resources per template (CPU/memory).

See also: docs/11-alignment-sentinel-zarr.md for cross-repo alignment steps with sentinel-zarr-explorer-coordination.

## Images
- Push to an OVH-accessible registry (Harbor/CR/Hub). Add `imagePullSecrets` when needed.

## Security
- Minimal ServiceAccount/RBAC for workflows. Restrict egress to object storage endpoints if required.

## CI/CD
- GitHub Actions: build multi-arch images, tag with commit SHA, apply manifests to staging using `kubectl diff` + `kubectl apply`.
