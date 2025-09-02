# Data Model Pipeline → GeoZarr (Remote Argo)

Run the GeoZarr conversion on a remote Argo Workflows cluster. The pipeline is a simple two-step DAG: convert → register. Output to a PVC path or directly to S3.

## Quick start

```bash
# Get a UI token from https://workspace.devseed.hub-eopf-explorer.eox.at/argo-workflows-server and export it
export ARGO_TOKEN='Bearer <paste-from-UI>'

# Apply template + submit with params.json
make up

# Follow logs / open UI
make logs
make ui
```

Custom image (optional, published to GHCR):

```bash
make publish TAG=mytag
make submit TAG=mytag
```

## What’s here

- `workflows/geozarr-convert-template.yaml` — WorkflowTemplate (convert → register)
- `params.json` — run arguments (see below)
- `Makefile` — build/publish, template, submit, logs, ui, doctor
- `docker/Dockerfile` — base image with `eopf-geozarr`

`.work/` contains local, ephemeral state.

## Parameters (edit `params.json`)

Minimal example:

```json
{
  "arguments": {
    "parameters": [
      {"name": "stac_url", "value": "https://…/scene.zarr"},
      {"name": "output_zarr", "value": "/data/scene_geozarr.zarr"},
      {"name": "groups", "value": "measurements/reflectance/r20m"},
      {"name": "validate_groups", "value": "false"},
      {"name": "register_url", "value": ""},
      {"name": "register_collection", "value": ""},
      {"name": "register_bearer_token", "value": ""},
      {"name": "register_href", "value": ""},
      {"name": "s3_endpoint", "value": "https://s3.de.io.cloud.ovh.net"}
    ]
  }
}
```

Notes:
- `output_zarr` can be a PVC path (e.g., `/data/...`) or `s3://bucket/key`.
- `groups` can be comma/space separated. `validate_groups=true` fails if a group is missing.
- Register is optional. If `register_href` is empty, href is derived from `output_zarr`. For `s3://` + `s3_endpoint`, it becomes `https://<endpoint>/<bucket>/<key>`.

## Common commands

- `make up` — apply template and submit
- `make submit` — submit using `params.json`
- `make logs` — tail latest run
- `make ui` — print Argo UI link
- `make doctor` — quick checks

Vars you can override: `GHCR_ORG`, `GHCR_REPO`, `TAG`, `SUBMIT_IMAGE`, `REMOTE_NAMESPACE`, `ARGO_REMOTE_SERVER`.

## S3 (OVH or other S3-compatible)

Write directly to S3 by setting `output_zarr` to `s3://...` and, for non-AWS, `s3_endpoint`.

Credentials (recommended via K8s Secret in your namespace):

```bash
kubectl -n devseed create secret generic ovh-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID='<ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
```

## Events (optional)

To auto-submit from RabbitMQ, edit `events/amqp-events.yaml` (AMQP URL, exchange, routingKey) and:

```bash
make events-apply
```

## License

Apache-2.0 — see [LICENSE](LICENSE)
