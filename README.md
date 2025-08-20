# eopf-geozarr-pipeline

Local MVP that:
1) Discovers items from a **source STAC API**,
2) Converts each to GeoZarr via the **eopf_geozarr** CLI,
3) Registers outputs in a **separate, local static STAC**.

## Install
pip install -e .
# Also install the converter (from its repo):
# pip install -e ../data-model

## Quick run
eopf-geozarr-pipeline run \
  --source-stac https://stac.core.eopf.eodc.eu \
  --source-collections sentinel-2-l1c \
  --max-items 3 \
  --output-root ./out-zarr \
  --target-stac-dir ./target-stac \
  --target-collection geozarr-s2

Outputs:
- Zarrs at ./out-zarr/<src-collection>/<item-id>.zarr
- Target STAC at ./target-stac (separate collection)

## Notes
- Local-first; S3 paths will pass through to your converter if used.
- Later you can replace the static STAC writer with STAC Transactions without changing discovery/convert logic.