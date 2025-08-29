# Dev notes

- Pinned versions: Argo **v3.6.5**, Python **3.11-slim**.
- Local loops:
  - `make build` → build container
  - `make template && make submit` → re-register and run
- Future tests:
  - small synthetic Zarr fixtures + golden outputs
  - parameter validation: missing groups should fail when `VALIDATE_GROUPS=true`
