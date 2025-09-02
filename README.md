# Data Model Pipeline → GeoZarr (Remote Argo)

Run `eopf-geozarr` on a remote Argo Workflows cluster. The workflow is remote‑first and intentionally lean; for converter details see the data-model repo.

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

 - `workflows/geozarr-convert-template.yaml` — WorkflowTemplate: convert → register (two-node DAG). Output can be a PVC path or an s3:// URL.
- `params.json` — arguments for runs (stac_url, output_zarr, groups, validate_groups, optional register_*).
- `Makefile` — concise remote UX: build/publish, template, submit, logs, get, ui, up, doctor.
- `docker/Dockerfile` — image with `eopf-geozarr` installed (use if you need changes from the default image).
  
Note: `.work/` holds ephemeral local state and should not be committed.

## Parameters (edit `params.json`)

```json
{
  "arguments": {
    "parameters": [
  {"name": "stac_url", "value": "https://…/S2…/scene.zarr"},
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

Notes: `output_zarr` is on the workflow’s PVC at `/data`; `groups` accepts space/comma; `validate_groups=true` will fail when a group is missing. 

Registration (optional) posts an Item to `{register_url}/collections/{register_collection}/items` if provided. If you don’t set `register_href`, the workflow will derive the asset href from the S3 settings (`s3_endpoint` + `s3_bucket` + `s3_key`) when a bucket is set.

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

Write directly to S3 using fsspec/s3fs by setting `output_zarr` to an s3:// URL, e.g. `s3://esa-zarr-sentinel-explorer-fra/<item>_geozarr.zarr`. Set `s3_endpoint` if your S3 is not AWS (e.g., OVH).

Credentials:

- Preferred: create a Kubernetes Secret named `ovh-s3-creds` in your remote namespace with keys `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. The workflow mounts it via envFrom.

```bash
kubectl -n devseed create secret generic ovh-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID='<ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
```

If `register_href` isn’t provided, the workflow derives the STAC asset href from `output_zarr`. For s3:// outputs and a provided `s3_endpoint`, it constructs `https://<endpoint>/<bucket>/<key>`.

## AOI

You can pass an `aoi` parameter through to the converter when supported by your image.

## Design and specs

- See `docs/` in this repo for the workflow contract and operational notes.
- GeoZarr spec: https://geozarr.readthedocs.io/

## License

Apache-2.0 — see [LICENSE](LICENSE).
