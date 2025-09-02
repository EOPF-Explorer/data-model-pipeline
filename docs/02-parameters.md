# Parameters

| Name                    | Scope | Default                                  | Note |
|-------------------------|-------|------------------------------------------|------|
| `REMOTE_NAMESPACE`      | env   | `devseed`                                | Namespace |
| `SUBMIT_IMAGE`          | env   | `ghcr.io/eopf-explorer/eopf-geozarr:dev` | Image |
| `PARAMS_FILE`           | env   | `params.json`                            | Args file |
| `stac_url`              | arg   | —                                        | Input STAC/Zarr |
| `output_zarr`           | arg   | `/data/out.zarr`                         | PVC or `s3://bucket/key` |
| `groups`                | arg   | `measurements/reflectance/r20m`          | Comma/space list |
| `validate_groups`       | arg   | `false`                                  | Fail on missing groups |
| `register_url`          | arg   | —                                        | STAC base URL |
| `register_collection`   | arg   | —                                        | Collection ID |
| `register_bearer_token` | arg   | —                                        | Bearer token |
| `register_href`         | arg   | —                                        | Asset href override |
| `s3_endpoint`           | arg   | `https://s3.de.io.cloud.ovh.net`         | S3-compatible endpoint |

Example `params.json` (minimal):

```json
{
  "arguments": {
    "parameters": [
      {"name": "stac_url", "value": "https://…/scene.zarr"},
      {"name": "output_zarr", "value": "/data/out.zarr"},
      {"name": "groups", "value": "measurements/reflectance/r20m"}
    ]
  }
}
```
