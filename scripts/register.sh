#!/usr/bin/env bash
# Create a minimal STAC Item and POST to a STAC API Transactions endpoint (experimental/WIP).
#
# Usage:
#   scripts/register.sh <output_path> [href_override] [stac_api_base] [collection] [bearer_token] [s3_endpoint]
#
# Args:
#   output_path     Path that identifies the dataset (e.g., s3://bucket/key or https URL); used to derive ID
#   href_override   Optional explicit href for the asset (otherwise derived from output_path/s3_endpoint)
#   stac_api_base   Base URL of the STAC API (e.g., https://api.example.com)
#   collection      Collection ID to register into
#   bearer_token    Optional bearer token
#   s3_endpoint     Optional S3 endpoint to convert s3:// to https href (path/virtual heuristics)
set -euo pipefail

OUT=${1:?"missing output path"}
HREF_OVERRIDE=${2:-}
URL=${3:-}
COLLECTION=${4:-}
TOKEN=${5:-}
ENDPOINT=${6:-}

if [ -z "${URL}" ]; then
  echo "No register_url provided; skipping STAC registration."
  exit 0
fi
if [ -z "${COLLECTION}" ]; then
  echo "register_url provided but register_collection is empty; skipping registration."
  exit 0
fi

ITEM_ID=$(basename "$OUT" | sed -E 's/(\.zarr)?(\.[^.]+)*$//')

if [ -n "$HREF_OVERRIDE" ]; then
  HREF_PLACEHOLDER="$HREF_OVERRIDE"
else
  if printf '%s' "$OUT" | grep -q '^s3://'; then
    if [ -n "$ENDPOINT" ]; then
      PATH_NO_SCHEME="${OUT#s3://}"
      BUCKET="${PATH_NO_SCHEME%%/*}"
      KEY="${PATH_NO_SCHEME#*/}"
      if printf '%s' "$ENDPOINT" | grep -q "$BUCKET"; then
        HREF_PLACEHOLDER="${ENDPOINT%/}/$KEY"
      else
        HREF_PLACEHOLDER="${ENDPOINT%/}/$BUCKET/$KEY"
      fi
      if ! printf '%s' "$HREF_PLACEHOLDER" | grep -qE '^https?://'; then
        HREF_PLACEHOLDER="$OUT"
      fi
    else
      HREF_PLACEHOLDER="$OUT"
    fi
  else
    HREF_PLACEHOLDER="$OUT"
  fi
fi

ITEM_JSON="/tmp/${ITEM_ID}.item.json"

printf '%s\n' \
  '{' \
  '  "type": "Feature",' \
  '  "stac_version": "1.0.0",' \
  "  \"id\": \"${ITEM_ID}\"," \
  "  \"collection\": \"${COLLECTION}\"," \
  '  "geometry": null,' \
  '  "bbox": null,' \
  '  "properties": {},' \
  '  "assets": {' \
  '    "data": {' \
  "      \"href\": \"${HREF_PLACEHOLDER}\"," \
  '      "type": "application/vnd+zarr",' \
  '      "roles": ["data"],' \
  '      "title": "GeoZarr dataset"' \
  '    }' \
  '  },' \
  '  "links": []' \
  '}' \
  > "$ITEM_JSON"

echo "Wrote $ITEM_JSON"

HDRS=("Content-Type: application/json")
if [ -n "$TOKEN" ]; then
  HDRS+=("Authorization: Bearer $TOKEN")
fi

curl -fsS -X POST "${URL%/}/collections/${COLLECTION}/items" \
  "${HDRS[@]/#/-H }" \
  --data-binary "@${ITEM_JSON}" \
  -o /tmp/register-response.json

echo "Registration response saved to /tmp/register-response.json"
