# Parameters

| Name                   | Source       | Default                                   | Notes |
|------------------------|-------------|-------------------------------------------|-------|
| `REMOTE_NAMESPACE`     | Make env     | `devseed`                                  | Remote namespace for runs. |
| `SUBMIT_IMAGE`         | Make env     | `docker.io/wietzesuijker/eopf-geozarr:dev`| Image used by submit. |
| `PARAMS_FILE`          | Make env     | `params.json`                              | Source of workflow parameters. |
| `image`                | workflow arg | `eopf-geozarr:dev`                         | Container image used in the workflow; overridden by `SUBMIT_IMAGE` at submit time. |
| `stac_url`             | workflow arg | *(none)*                                   | Input Sentinel-2 Zarr location (HTTP/S3/Swift). |
| `output_zarr`          | workflow arg | `/data/out.zarr`                           | Output path on PVC. |
| `groups`               | workflow arg | `measurements/reflectance/r20m`            | Path(s) within Zarr to convert (comma/space separated). |
| `validate_groups`      | workflow arg | `false`                                    | When `true`, fail if group is missing. |
| `aoi`                  | workflow arg |                                           | Optional AOI passed to converter. |
| `register_url`         | workflow arg |                                           | STAC Transactions endpoint base URL. |
| `register_collection`  | workflow arg |                                           | Collection ID to register into. |
| `register_bearer_token`| workflow arg |                                           | Bearer token for auth, if required. |
| `register_href`        | workflow arg |                                           | Optional explicit href for the GeoZarr asset. |
| `s3_endpoint`          | workflow arg | `https://s3.de.io.cloud.ovh.net`           | OVHcloud S3 endpoint for uploads. |
| `s3_bucket`            | workflow arg |                                           | Bucket to upload to; when empty, upload is skipped. |
| `s3_key`               | workflow arg |                                           | Object key (defaults to basename of `output_zarr`). |

### Example params.json

Edit `params.json` and run `make submit`.

```json
{
  "arguments": {
    "parameters": [
      {"name": "stac_url", "value": "https://…/scene.zarr"},
      {"name": "output_zarr", "value": "/data/scene_geozarr.zarr"},
      {"name": "groups", "value": "measurements/reflectance/r20m"},
      {"name": "validate_groups", "value": "false"},
      {"name": "aoi", "value": ""},
      {"name": "register_url", "value": ""},
      {"name": "register_collection", "value": ""},
      {"name": "register_bearer_token", "value": ""},
      {"name": "register_href", "value": ""},
      {"name": "s3_endpoint", "value": "https://s3.de.io.cloud.ovh.net"},
      {"name": "s3_bucket", "value": ""},
      {"name": "s3_key", "value": ""}
    ]
  }
}
```
