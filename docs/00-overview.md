
# Overview

**Goal:** Convert Sentinel Zarr → GeoZarr using a simple Argo pipeline.

- **Local prototype**: run in k3d/k3s with minimal setup.
- **Inputs**: Sentinel STAC URL, group(s) to convert.
- **Outputs**: GeoZarr-compliant dataset in PVC.

## Flow

1. **Bootstrap** tools (docker, k3d, kubectl, argo CLI).  
2. **Cluster**: ensure local k3d cluster exists.  
3. **Argo**: install controller + CRDs (v3.6.5).  
4. **Image**: build and import `eopf-geozarr:dev`.  
5. **PVC**: create if needed.  
6. **WorkflowTemplate**: applied to cluster.  
7. **Submit**: run conversion job.

---

This structure maps directly to `make up` → `make logs`.
