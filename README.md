# Data Model Pipeline → GeoZarr (Remote Argo)

Run `eopf-geozarr` on a remote Argo Workflows cluster. This repo is remote‑first and intentionally lean; for converter details see the data-model repo.

## TL;DR

```bash
# 0) One-time: get a UI token from Argo and export it in your shell
export ARGO_TOKEN='Bearer <paste-from-UI>'

# 1) Quick one-shot (apply template + submit using params.json)
make up

# 2) Watch logs
make logs

# 3) Open UI (namespace view)
make ui
```

Want a custom image? Build and publish to Docker Hub, then submit:

```bash
make publish TAG=mytag
make submit TAG=mytag
```

## What this repo contains

- `workflows/geozarr-convert-template.yaml` — WorkflowTemplate: convert → register (two-node DAG).
- `params.json` — arguments for runs (stac_url, output_zarr, groups, validate_groups, optional register_*).
- `Makefile` — concise remote UX: build/publish, template, submit, logs, get, ui, up, doctor.
- `docker/Dockerfile` — image with `eopf-geozarr` installed (use if you need changes from the default image).

## Parameters (edit `params.json`)

```json
{
  "arguments": {
    "parameters": [
      {"name": "stac_url", "value": "https://…/S2…/scene.zarr"},
      {"name": "output_zarr", "value": "/data/scene_geozarr.zarr"},
      {"name": "groups", "value": "measurements/reflectance/r20m"},
      {"name": "validate_groups", "value": "false"},
      {"name": "register_url", "value": ""},
      {"name": "register_collection", "value": ""},
      {"name": "register_bearer_token", "value": ""}
    ]
  }
}
```

Notes: `output_zarr` is on the workflow’s PVC at `/data`; `groups` accepts space/comma; `validate_groups=true` will fail when a group is missing. Registration posts an Item to `{register_url}/collections/{register_collection}/items` if provided.

## Common commands

- `make up` — apply the template and submit immediately.
- `make template` — apply/update the WorkflowTemplate (idempotent).
- `make submit` — submit from the WorkflowTemplate using `params.json`.
- `make logs` — tail the latest run.
- `make get` — describe the latest workflow.
- `make ui` — print a direct Argo UI namespace link.
- `make doctor` — minimal env sanity checks.
- `make events-apply` — (optional) apply RabbitMQ → Argo Events source & sensor to auto-submit on queue messages.

Overrideables: `DOCKERHUB_ORG`, `DOCKERHUB_REPO`, `TAG`, `SUBMIT_IMAGE`, `REMOTE_NAMESPACE`, `ARGO_REMOTE_SERVER`.

## Optional: trigger via RabbitMQ (Argo Events)

If you already produce STAC item messages to a RabbitMQ exchange, you can have Argo auto-submit:

1) Edit `events/amqp-events.yaml` and set your AMQP `url`, `exchangeName`, and `routingKey`.
2) Apply to the cluster namespace:

```bash
make events-apply
```

Incoming messages populate workflow parameters (e.g., `stac_url`, `register_*`). Adjust the Sensor’s parameter mapping as needed.

## OVHcloud Object Storage (S3-compatible)

You can upload the resulting Zarr to OVHcloud S3 before registering:

Parameters (optional):
- `s3_endpoint` (default `https://s3.de.io.cloud.ovh.net`)
- `s3_bucket` (e.g., `esa-zarr-sentinel-explorer-fra`)
- `s3_key` (object key; defaults to basename of output_zarr)

Example snippet in `params.json`:

Create a Kubernetes Secret named `ovh-s3-creds` in your remote namespace with keys `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (values from OpenStack EC2 credentials). The workflow will pick them up automatically via envFrom:

```bash
kubectl -n devseed create secret generic ovh-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID='<ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
```

The workflow uses awscli with `--endpoint-url` to push to OVHcloud. If `register_href` isn’t provided, it will use an HTTPS URL based on the endpoint/bucket/key for the STAC asset href.

## AOI

You can pass an `aoi` parameter through to the converter when supported by your image.

## Design and specs

- See `docs/` in this repo for the workflow contract and operational notes.
- GeoZarr spec: https://geozarr.readthedocs.io/

## License

Apache-2.0 — see [LICENSE](LICENSE).
