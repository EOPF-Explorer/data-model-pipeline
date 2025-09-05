# GeoZarr conversion pipeline (Argo Workflows)

Convert an input STAC or Zarr dataset to GeoZarr on a remote Argo Workflows cluster and save the result to your S3 bucket. Today the workflow has two steps available: convert (runs today) → register (optional, WIP for STAC Transactions). The RabbitMQ trigger is also WIP.

- S3 direct writes (s3://bucket/key)
- AWS keys stored in the cluster (Kubernetes Secret)
- Minimal runtime: eopf-geozarr

On this page
- Quickstart
- Parameters
- S3 credentials (incl. OVH Swift S3)
- How it works
- 3-step flow (roadmap)
- Cloud/config
- Troubleshooting
- Repository layout

## Quickstart

Prereqs (defaults in Makefile)
- ARGO_REMOTE_SERVER=https://argo-workflows.hub-eopf-explorer.eox.at
- REMOTE_NAMESPACE=devseed  # your cluster project name

1) Token (one time copy from [Argo user info](https://argo-workflows.hub-eopf-explorer.eox.at/userinfo))
```bash
export ARGO_TOKEN='Bearer <copy from Argo UI>'
make token-bootstrap   # writes .work/argo.token
unset ARGO_TOKEN       # argo wrapper reads .work/argo.token
```

2) S3 Secret (required; run once per project)

```bash
export AWS_ACCESS_KEY_ID=...     # see OVH steps below if using OVH
export AWS_SECRET_ACCESS_KEY=...
# optional (if issued): export AWS_SESSION_TOKEN=...
make secret-ovh-s3               # REQUIRED: create/update 'ovh-s3-creds' for REMOTE_NAMESPACE (lets the job write to S3)
```

This stores your storage keys so the job can write to your bucket. Run once.

3) Build/apply/submit

```bash
# Start from the example (once):
cp params.example.json params.json

make up          # build+push image, apply template, submit
# or force rebuild
make up-force    # rebuild with --pull --no-cache
```

Resubmit with different params

```bash
make submit                         # uses params.json
# or point to another file
make submit PARAMS_FILE=params.example.json
```

Follow runs

```bash
make logs
make ui
```

## Parameters

Essentials
- stac_url: Input STAC/Zarr URL
- output_zarr: S3 path (s3://bucket/key)
- groups: Space/comma list of group paths (auto-normalized to start with /)

S3
- s3_endpoint: e.g., https://s3.de.io.cloud.ovh.net
- s3_region: short code (e.g., de)
- aws_addressing_style: how S3 URLs are formed. 'path' → https://endpoint/bucket/key (use this; works for OVH). 'virtual' → https://bucket.endpoint/key (only if your storage needs it).
- s3_secret_name: Kubernetes Secret name with AWS creds (default ovh-s3-creds)
- Inline creds (dev only): aws_access_key_id, aws_secret_access_key, aws_session_token

Registration (optional, WIP — STAC Transactions to eoAPI)
- register_url, register_collection, register_bearer_token, register_href

## S3 credentials

Create this once per project. Keys needed:
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- (optional) AWS_SESSION_TOKEN

Example (manual):

```bash
kubectl -n devseed create secret generic ovh-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID='<ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<SECRET_KEY>'
# optional: --from-literal=AWS_SESSION_TOKEN='<SESSION_TOKEN>'
```

Use `s3_secret_name` in params to override the name.

### OVH (Swift S3 API) — quick setup

OVH uses OpenStack Swift with an S3-compatible API.

- Prep your env: https://help.ovhcloud.com/csm/en-gb-public-cloud-compute-prepare-openstack-api-environment?id=kb_article_view&sysparm_article=KB0050997
- Get and source RC file: https://help.ovhcloud.com/csm/en-gb-public-cloud-compute-set-openstack-environment-variables?id=kb_article_view&sysparm_article=KB0050928, then `source openrc.sh`
- Create S3-style keys: `openstack ec2 credentials create` → copy Access/Secret to `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Configure params: set `s3_endpoint` (e.g., `https://s3.de.io.cloud.ovh.net`, `https://s3.gra.io.cloud.ovh.net`) and `s3_region` (`de`, `gra`, `rbx`, `bhs`); keep addressing style `path`
- Save keys in the cluster:
  - `export AWS_ACCESS_KEY_ID=...`
  - `export AWS_SECRET_ACCESS_KEY=...`
  - optional: `export AWS_SESSION_TOKEN=...`
  - `make secret-ovh-s3`

Docs: https://help.ovhcloud.com/csm/en-gb-public-cloud-storage-pcs-getting-started-swift-s3-api?id=kb_article_view&sysparm_article=KB0047146

## How it works

- Two steps:
  - convert: runs `eopf-geozarr convert`, writes to S3 using your keys
  - register (optional, experimental): posts a minimal STAC Item to a STAC Transactions API (e.g., eoAPI); saves response to /tmp/register-response.json
- Token: `make token-bootstrap` saves a durable token at `.work/argo.token` for the CLI wrapper
- Image: small container with eopf-geozarr (workflow calls the CLI directly)

## 3-step flow (roadmap)

Goal: keep the workflow simple, event-driven, and easy to operate.

1) Get work from a queue (RabbitMQ) — WIP
- Use Argo Events AMQP source so the workflow subscribes to a RabbitMQ queue.
- Docs: https://argoproj.github.io/argo-events/eventsources/setup/amqp/

2) Convert
- Run the data-model's converter directly (`eopf-geozarr convert`).
- Keep workflow inputs minimal (stac_url, output_zarr, S3 settings).

3) Register to STAC API
- After a successful convert, POST the Item to a STAC Transactions API.
- Extension: https://github.com/stac-api-extensions/transaction

Notes
- Retry: expose a simple retries setting in the workflow (e.g., attempts/backoff) so transient issues can be retried.
- AOI-facing: an upstream service can search STAC for new items (by area/time) and push IDs/URLs onto the queue.
- OVH target: choose the S3 bucket/prefix in params (e.g., `output_zarr`), pointing to your OVH endpoint.

## ADR alignment (brief)

- Orchestration: Argo Workflows runs a simple two-step flow (convert → optional register).
- Scaling: stateless jobs, S3 direct writes, small image.
- Deployment: secure token bootstrap; storage keys via cluster Secret.
- GeoZarr: uses the established converter (eopf-geozarr) and parameters.
- API: optional STAC Transactions registration with clear parameters.

## Cloud/config

- Image: GHCR_ORG, GHCR_REPO, TAG, SUBMIT_IMAGE
- Build: REMOTE_PLATFORM (linux/amd64), FORCE=true for no-cache
- Argo: ARGO_REMOTE_SERVER, REMOTE_NAMESPACE, REMOTE_SERVICE_ACCOUNT, ARGO_TLS_INSECURE, ARGO_CA_FILE

Tip: `make env` shows effective values; `make doctor` sanity-checks connectivity and token.

## Troubleshooting

- Token: Ensure `.work/argo.token` exists or set ARGO_TOKEN/ARGO_TOKEN_FILE
- S3: Use `s3://…` and set `s3_endpoint`/`s3_region`; the Secret must be in the same project you run in
- Logs: `make logs`; status: `make get`

## Repository layout

- workflows/
  - geozarr-convert-template.yaml — main workflow (convert → optional register)
  - bootstrap-argo-token.yaml — creates a durable token used by token-bootstrap
- scripts/
  - argo_remote.sh — CLI wrapper (reads token file/env; sets TLS/namespace)
  - argo_submit_workflow.sh — submits the workflow with your params and prints a UI link
  - params_to_flags.py — turns params JSON into -p flags
  - bootstrap_argo_token.sh — saves .work/argo.token
  - register.sh — helper to POST a STAC Item (WiP)
- Make targets
  - init, up, up-force, submit, logs, get, ui, token-bootstrap, secret-ovh-s3, clean

## License

Apache-2.0 — see LICENSE
