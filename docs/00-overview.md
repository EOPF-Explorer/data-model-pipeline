# Overview

Convert Sentinel Zarr to GeoZarr on a remote Argo Workflows cluster.

- Remote-first operation; no local bootstrap required.
- Inputs: STAC URL and group(s); optional AOI.
- Outputs: GeoZarr written to a PVC or directly to S3 (via fsspec/s3fs). Optional STAC registration.

## Pipeline (DAG)

convert → register (register runs only if register URL+collection are set)

## Remote flow

1) Export token from Argo UI
	`export ARGO_TOKEN='Bearer <paste-from-UI>'`
2) Apply template: `make template`
3) Submit: `make submit`
4) Logs/UI: `make logs`, `make ui`

Optional: `make events-apply` to auto-submit from RabbitMQ.
