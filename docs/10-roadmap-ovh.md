# Roadmap to OVH (next steps)

**Goal**: run the same Argo templates on an OVH-hosted Kubernetes cluster and scale out.

## Storage
- Start with OVH Block Storage (RWO PVC) to mirror local behavior.
- For higher concurrency and read/write throughput, plan for **object store outputs** (Swift/S3 API). Container writes directly to object storage; PVC only for scratch.

## Scaling
- Increase throughput by fan-out per *group/band/tile*. Use a DAG with parallel steps.
- Control parallelism at **workflow** and **controller** levels; set resources per template (CPU/memory).

## Images
- Push to an OVH-accessible registry (Harbor/CR/Hub). Add `imagePullSecrets` when needed.

## Security
- Minimal ServiceAccount/RBAC for workflows. Restrict egress to object storage endpoints if required.

## CI/CD
- GitHub Actions: build multi-arch images, tag with commit SHA, apply manifests to staging using `kubectl diff` + `kubectl apply`.
