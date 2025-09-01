
# Overview

**Goal:** Convert Sentinel Zarr → GeoZarr using a simple Argo pipeline on a remote cluster.

- Remote-first usage; local k3d/kubectl bootstrap has been removed.
- Inputs: Sentinel STAC URL and group(s) to convert.
- Outputs: GeoZarr dataset written to a remote PVC.

## Flow (remote)

1. Export your Argo UI token: `export ARGO_TOKEN='Bearer <paste-from-UI>'`  
2. Apply the WorkflowTemplate: `make template`  
3. Submit a run: `make submit`  
4. Tail logs: `make logs`  
5. Open UI: `make ui`
