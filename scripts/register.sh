#!/usr/bin/env bash
# Create a minimal STAC Item and POST to a STAC API Transactions endpoint.
# Args: 1) output path  2) href override  3) STAC API base  4) collection  5) bearer  6) s3 endpoint
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

ITEM_JSON="/data/${ITEM_ID}.item.json"

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
  -o /data/register-response.json

echo "Registration response saved to /data/register-response.json"
