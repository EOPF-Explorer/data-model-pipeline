#!/usr/bin/env bash
# Convert a STAC/Zarr dataset to GeoZarr using eopf-geozarr.
# Args: 1) input URL  2) output path  3) groups (comma/space)  4) s3 endpoint
set -euo pipefail

STAC=${1:?"missing STAC/Zarr input URL"}
OUT=${2:?"missing output path"}
GROUPS_RAW=${3:-}
S3_ENDPOINT=${4:-}

echo "=== inputs ==="
echo "stac_url=$STAC"
echo "output_zarr=$OUT"
echo "groups_raw=$GROUPS_RAW"

echo "=== env sanity ==="
if ! command -v eopf-geozarr >/dev/null 2>&1; then
  echo "[error] eopf-geozarr not found on PATH" >&2
  exit 127
fi

GROUP_LIST=""
if [ -n "${GROUPS_RAW:-}" ]; then
  for g in $(printf '%s' "$GROUPS_RAW" | tr ',' ' '); do
    [ -z "$g" ] && continue
    g="/${g#/}"
    GROUP_LIST="$GROUP_LIST $g"
  done
  GROUP_LIST="${GROUP_LIST# }"
fi
echo "groups=$GROUP_LIST"

echo "=== convert ==="
# If no groups provided, rely on converter defaults.
# Configure S3 endpoint for s3fs/boto if provided
if [ -n "$S3_ENDPOINT" ]; then
  export AWS_S3_ENDPOINT="$S3_ENDPOINT"
  export AWS_ENDPOINT_URL="$S3_ENDPOINT"
fi

CMD=( eopf-geozarr convert "$STAC" "$OUT" --verbose )
if [ -n "$GROUP_LIST" ]; then
  CMD+=( --groups )
  for g in $GROUP_LIST; do CMD+=( "$g" ); done
fi
exec "${CMD[@]}"
