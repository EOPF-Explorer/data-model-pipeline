# OVH roadmap (concise)

Goal: run the Argo workflow on OVH Kubernetes and scale.

Storage
- Use OVH Block Storage PVC for scratch if needed; write outputs directly to S3 via fsspec.

Scaling
- Fan-out per group/band/tile; control parallelism at workflow/controller; set per-step resources.

Images
- Push to an OVH-accessible registry; add imagePullSecrets when required.

Security
- Minimal ServiceAccount/RBAC; egress restricted to object store endpoints if needed.

CI/CD
- Build multi-arch images, tag with SHA; use `kubectl diff && kubectl apply` for staging.
