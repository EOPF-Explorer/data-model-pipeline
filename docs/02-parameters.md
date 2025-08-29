# Parameters

| Name              | Source            | Default              | Notes |
|-------------------|-------------------|----------------------|-------|
| `NAMESPACE`       | Make env          | `argo`               | Kubernetes namespace for Argo + PVC. |
| `PVC_NAME`        | Make env          | `geozarr-pvc`        | PVC bound and mounted at `/data`. |
| `IMAGE`           | Make env          | `eopf-geozarr:dev`   | Container image tag used by template. |
| `ARGO_VER`        | Make env          | `v3.6.5`             | Argo Workflows version to install. |
| `STAC_URL`        | submit param      | *(none)*             | Input Sentinel-2 Zarr location (HTTP/S3/Swift). |
| `OUTPUT_ZARR`     | submit param      | `/data/out.zarr`     | Output path on PVC. |
| `GROUPS`          | submit param      | `measurements/reflectance/r20m` | Path(s) within Zarr to convert (CLI supports multiple). |
| `VALIDATE_GROUPS` | submit param      | `false`              | When `true`, fail if group is missing. |

### Examples

```bash
make submit \
  STAC_URL="https://example.invalid/in.zarr" \
  OUTPUT_ZARR="/data/out_geozarr.zarr" \
  GROUPS="measurements/reflectance/r20m" \
  VALIDATE_GROUPS=true
```
