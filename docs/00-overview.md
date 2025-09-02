# Overview

**Goal:** Convert Sentinel Zarr → GeoZarr using a simple Argo pipeline on a remote cluster.

- Remote-first usage; local bootstrap removed.
- Inputs: Sentinel STAC URL and group(s) to convert; optional AOI.
- Outputs: GeoZarr dataset written to a PVC or directly to S3 (OVH), and optionally registered in a STAC API.

## Pipeline (DAG):

- convert → register (register is optional when URL+collection set)

## Flow (remote)

1. Export your Argo UI token: `export ARGO_TOKEN='Bearer <paste-from-UI>'`
2. Apply the WorkflowTemplate: `make template`
3. Submit a run: `make submit`
4. Tail logs: `make logs`
5. Open UI: `make ui`

Optional: `make events-apply` to listen to RabbitMQ and auto-submit.
