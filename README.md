# Data Model Pipeline → GeoZarr (Remote Argo)

Run a GeoZarr conversion on a remote Argo Workflows cluster. Two steps: convert → (optional) register. The convert step uses the data‑model CLI directly. Write to PVC (`/data/...`) or directly to `s3://...`.

Future-ready flow (target)
- 1) Get pointer from RabbitMQ (EODC STAC message) instead of params.json
- 2) Call the data-model converter directly (no wrapper)
- 3) Register to external STAC (eoAPI Transactions)

You can run today via params.json; AMQP trigger and eoAPI registration are prepared without breaking current usage.

## Zero-to-first-run (3 steps)

1) Get an Argo UI token [here](https://argo-workflows.hub-eopf-explorer.eox.at/userinfo#:~:text=COPY%20TO%20CLIPBOARD) and export it

```bash
export ARGO_TOKEN='Bearer <paste-from-UI>'
```

2) Build+push the image and apply the workflow template

```bash
make up TAG=dev   # add FORCE=true to rebuild without cache and pull base
```

3) Submit a run

```bash
# Use defaults in params.json (good for Sentinel‑2)
make submit

# Or use a ready-made example file:
# - Sentinel‑2 resolutions
make submit PARAMS_FILE=params.s2.json
# - Sentinel‑1 GRD (groups set to measurements)
make submit PARAMS_FILE=params.s1.json
```

Follow logs / open UI:

```bash
make logs
make ui
```

Notes
- make up = build+push (GHCR) → apply template → submit
- Set TAG to pick or pin an image (e.g., TAG=v0.1.0). Use FORCE=true to pull+no-cache.
- For repeat runs without rebuild: use make submit (optionally PARAMS_FILE=…)

## What’s included

- `workflows/geozarr-convert-template.yaml` — WorkflowTemplate (convert → register)
- `params.json` — default arguments
- `params.s2.json` — Sentinel‑2 sample
- `params.s1.json` — Sentinel‑1 GRD sample
- `Makefile` — publish, template, submit, logs, ui, doctor
- `docker/Dockerfile` — base image with `eopf-geozarr`

`.work/` is local, ephemeral state.

## AMQP trigger (WiP)

The manifest in `events/amqp-events.yaml` wires RabbitMQ → Argo Workflow submission. Replace the AMQP URL placeholders and apply it. The Sensor maps `eventBody.properties.*` to workflow parameters:

- `properties.href` → `stac_url`
- `properties.groups` → `groups` (optional)
- `properties.register_url`, `properties.collection` → registration (optional)

This keeps `make submit` working while enabling event-driven runs.

## Parameter basics

- `stac_url`: STAC/Zarr URL of the input
- `output_zarr`: where to write the GeoZarr (PVC path or `s3://bucket/key`)
- `groups` (recommended): space- or comma-separated group paths. Examples:
  - Sentinel‑2: `/measurements/reflectance/r20m` (or the r10m/r20m/r60m set)
  - Sentinel‑1 GRD: `/measurements`
- Registration (optional): `register_url`, `register_collection`, `register_bearer_token`, `register_href`
- `s3_endpoint`: S3-compatible endpoint (e.g., OVH)

Tips

- Groups are normalized to start with `/`, so both `measurements` and `/measurements` are accepted.
- For Sentinel‑2, you can explicitly set: `/measurements/reflectance/r20m` (single) or the full set.
- For Sentinel‑1 GRD, use `measurements` (normalized to `/measurements`) (see `params.s1.json`).

## S3 (OVH or other S3‑compatible)

To write to S3, use an `s3://bucket/key` output and set `s3_endpoint` for non-AWS providers.

Credentials via K8s Secret (namespace: `devseed` by default):

```bash
kubectl -n devseed create secret generic ovh-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID='<ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
```

## Common commands

- `make up` — build (optional), apply template, submit
- `make template` — apply/update the WorkflowTemplate
- `make submit` — submit using a params file (default: `params.json`)
- `make logs` — tail latest run
# GeoZarr conversion pipeline (Argo Workflows)

Convert Zarr datasets (e.g., Sentinel‑2) to GeoZarr on a remote Argo cluster. The workflow is intentionally simple: convert → optional register.

Related projects

- eopf-explorer/data-model (converter library and CLI)
- EOPF coordination docs (architecture, ADRs): sentinel-zarr-explorer-coordination

## Quickstart

1) Auth to Argo UI and export a token

```bash
export ARGO_TOKEN='Bearer <paste-from-UI>'
```

2) Apply the workflow template

```bash
make template
```

3) Submit using the default params.json (S2 example)

```bash
make submit
```

Watch logs / open UI

```bash
make logs
make ui
```

## Parameters (minimal)

- stac_url: Input STAC/Zarr URL
- output_zarr: Output path (`/data/...` PVC or `s3://bucket/key`)
- groups: One or more group paths (space/comma separated). Examples:
  - Sentinel‑2: measurements/reflectance/r20m (single) or add r10m/r60m
  - Sentinel‑1 GRD: measurements
- Registration (optional): register_url, register_collection, register_bearer_token, register_href
- s3_endpoint: S3-compatible endpoint (OVH example provided)

Notes

- Groups are normalized to have a single leading `/`, so both `measurements/...` and `/measurements/...` are fine.
- The default `params.json` is set to S2 reflectance r20m for a fast first run.

## What’s in this repo

- workflows/geozarr-convert-template.yaml — Argo WorkflowTemplate
- params.json — simple defaults for S2
- Makefile — template, submit, logs, ui (+ publish/up for custom images)
- docker/Dockerfile — converter image build (includes eopf-geozarr)
 

## S3 (OVH or other S3‑compatible)

For non‑AWS endpoints, set `s3_endpoint` and provide credentials via a Secret (namespace `devseed`):

```bash
kubectl -n devseed create secret generic ovh-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID='<ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
```

## Common commands

- make init — one-time setup (exec bits) + env check
- make up — build+push image, apply template, submit
- make template — apply/update the WorkflowTemplate
- make submit — submit using PARAMS_FILE (default: params.json)
- make logs — follow latest run; make ui — open namespace UI link

You can override: GHCR_ORG, GHCR_REPO, TAG, SUBMIT_IMAGE, REMOTE_NAMESPACE, ARGO_REMOTE_SERVER.

## Troubleshooting (quick)

- Auth: refresh UI token and export ARGO_TOKEN='Bearer …'
- Env check: make doctor
- Template: make template (or make template-force)
- Logs: make logs (follow @latest)
- Image pulls: ensure image is public or set imagePullSecret on the template
- S3: output_zarr=s3://… and s3_endpoint for non‑AWS; create secret ovh-s3-creds with AWS keys
- Namespace: REMOTE_NAMESPACE must match where Argo + secrets live

## Code pointers

- Workflow: workflows/geozarr-convert-template.yaml
- Events (WiP): events/amqp-events.yaml
- Scripts: scripts/register.sh
- Make helpers: Makefile, scripts/argo_*.sh

## Next steps

- Split templates: keep this repo for convert‑only; create a separate register-only template if/when needed.
- Pin images: use a version tag (e.g., :v0.1.x) for reproducible runs; keep :dev for iteration.
- Add a tiny smoke test: a public tiny Zarr + CI to validate the WorkflowTemplate syntax.
- (Optional) Drop s3_endpoint param and rely on AWS_ENDPOINT_URL in the Secret; document once.
- (Optional) Publish prebuilt images to GHCR with clear tags from data‑model releases.

## License

Apache‑2.0 — see [LICENSE](LICENSE)
