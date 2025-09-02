# OVH roadmap (one page)

Goal: run and scale the workflow on OVH Kubernetes.

- Storage: PVC scratch if needed; write final to S3 (fsspec/s3fs).
- Scaling: fan-out per group/band/tile; set parallelism and per-step resources.
- Images: push to GHCR; configure imagePullSecrets if cluster requires.
- Security: minimal RBAC; restrict egress to object store endpoints if needed.
- CI/CD: multi-arch builds, SHA tags; `kubectl diff && kubectl apply` for rollout.
