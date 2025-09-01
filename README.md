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

- `workflows/geozarr-convert-template.yaml` — WorkflowTemplate: convert → optional STAC register.
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

Overrideables: `DOCKERHUB_ORG`, `DOCKERHUB_REPO`, `TAG`, `SUBMIT_IMAGE`, `REMOTE_NAMESPACE`, `ARGO_REMOTE_SERVER`.

## Design and specs

- See `docs/` in this repo for the workflow contract and operational notes.
- GeoZarr spec: https://geozarr.readthedocs.io/

## License

Apache-2.0 — see [LICENSE](LICENSE).
