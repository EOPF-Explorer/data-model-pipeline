# Troubleshooting

**No k3d cluster**: `FATA[0000] failed to get cluster ... No nodes found`  
→ `k3d cluster create k3s-default` (Makefile targets are idempotent).

**Namespace not found**: `namespaces "argo" not found`  
→ Our `ensure_pvc.sh` creates the namespace if needed. Run `make up` again.

**No WorkflowTemplate CRD**: `no matches for kind "WorkflowTemplate"`  
→ `make up` installs Argo v3.6.5 and waits for CRDs. Verify: `kubectl api-resources | grep WorkflowTemplate`.

**YAML parse error** when applying template  
→ We ship a validated template. To lint changes: `kubectl create --dry-run=client -f workflows/geozarr-convert-template.yaml`.

**Image not visible inside cluster**  
→ Use our default `k3d image import` path; or set `USE_REGISTRY=1` and push to the local k3d registry.

**Object storage auth** (future)  
→ For OVH object storage, mount credentials as a Secret and inject env vars; see `docs/10-roadmap-ovh.md`.
