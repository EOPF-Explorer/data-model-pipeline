# Parameters

| Name              | Source            | Default              | Notes |
|-------------------|-------------------|----------------------|-------|
| `REMOTE_NAMESPACE`| Make env          | `devseed`            | Remote namespace for runs. |
| `SUBMIT_IMAGE`    | Make env          | `docker.io/wietzesuijker/eopf-geozarr:dev` | Image used by submit. |
| `PARAMS_FILE`     | Make env          | `params.json`        | Source of workflow parameters. |
| `STAC_URL`        | submit param      | *(none)*             | Input Sentinel-2 Zarr location (HTTP/S3/Swift). |
| `OUTPUT_ZARR`     | submit param      | `/data/out.zarr`     | Output path on PVC. |
| `GROUPS`          | submit param      | `measurements/reflectance/r20m` | Path(s) within Zarr to convert (CLI supports multiple). |
| `VALIDATE_GROUPS` | submit param      | `false`              | When `true`, fail if group is missing. |

### Examples

Edit `params.json` and run `make submit`.
