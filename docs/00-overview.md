# Overview

Remote GeoZarr conversion on Argo Workflows. Two steps: convert → register.

Essentials
- Image: ghcr.io/EOPF-Explorer/eopf-geozarr
- Inputs: `stac_url`, `groups` (comma/space), optional `aoi`
- Outputs: `/data/...` (PVC) or `s3://bucket/key` (set `s3_endpoint` for S3-compatible)
- Optional: STAC register via `register_url` + `register_collection` (+ bearer token)

Quickstart
1) `export ARGO_TOKEN='Bearer <paste-from-UI>'`
2) `make up` (apply + submit)
3) `make logs` · `make ui`

Notes
- Register runs only if URL + collection are provided.
- Design refs: ADR-001/002/003 (orchestration, scaling, infra).
