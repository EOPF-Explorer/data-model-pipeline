# Parameters

| Name                    | Scope        | Default                                    | Notes |
|-------------------------|--------------|--------------------------------------------|-------|
| `REMOTE_NAMESPACE`      | Make env     | `devseed`                                  | Namespace used by make targets |
| `SUBMIT_IMAGE`          | Make env     | `docker.io/wietzesuijker/eopf-geozarr:dev` | Image used by submit |
| `PARAMS_FILE`           | Make env     | `params.json`                               | File with workflow args |
| `stac_url`              | workflow arg | —                                          | Input Sentinel-2 Zarr (HTTP/S3/Swift) |
| `output_zarr`           | workflow arg | `/data/out.zarr`                            | PVC path or `s3://bucket/key` |
| `groups`                | workflow arg | `measurements/reflectance/r20m`             | Comma/space separated |
| `validate_groups`       | workflow arg | `false`                                     | Fail if any group is missing |
| `aoi`                   | workflow arg | —                                           | Optional AOI |
| `register_url`          | workflow arg | —                                           | STAC Transactions base URL |
| `register_collection`   | workflow arg | —                                           | Target collection ID |
| `register_bearer_token` | workflow arg | —                                           | Bearer token if required |
| `register_href`         | workflow arg | —                                           | Explicit asset href (optional) |
| `s3_endpoint`           | workflow arg | `https://s3.de.io.cloud.ovh.net`            | For non-AWS S3 (e.g., OVH) |

### Example `params.json`

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
      {"name": "s3_endpoint", "value": "https://s3.de.io.cloud.ovh.net"}
    ]
  }
}
```
