#!/usr/bin/env bash
# Robust wrapper for `eopf-geozarr convert`
# - Accepts --stac-url, --output-zarr, --groups [multi-token or single string]
# - Falls back to $GROUPS or $ARGO_GROUPS when --groups omitted
# - Normalizes to absolute group paths
# - Preflight discovers .zgroup entries; if missing:
#     * auto-map by unique suffix match (best effort)
#     * if VALIDATE_GROUPS=true and still missing → exit 8
#     * else warn and continue
# - Unbuffered logs & error trap

set -Eeuo pipefail
export PYTHONUNBUFFERED=1

trap 'ec=$?; echo "[convert.sh] ERROR at line ${LINENO} (exit=${ec})" >&2' ERR
echo "[convert.sh] Bash $(bash --version | head -n1)"
echo "[convert.sh] PWD=$(pwd)"

STAC_URL="${STAC_URL:-}"
OUTPUT_ZARR="${OUTPUT_ZARR:-}"
GROUPS="${GROUPS:-}"
declare -a GROUPS_ARR=()
VALIDATE_GROUPS="${VALIDATE_GROUPS:-false}"

# --- parse flags ---
while (($#)); do
  case "$1" in
    --stac-url)       STAC_URL="${2-}"; shift 2 ;;
    --output-zarr)    OUTPUT_ZARR="${2-}"; shift 2 ;;
    --groups)
      shift
      while (($#)) && [[ "$1" != --* ]]; do GROUPS_ARR+=("$1"); shift; done
      ;;
    --validate-groups) # allow optional true/false after it
      if [[ "${2-}" != "" && "${2-}" != --* ]]; then VALIDATE_GROUPS="${2}"; shift 2; else VALIDATE_GROUPS="true"; shift; fi
      ;;
    *) echo "[convert.sh] Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Fallbacks
if ((${#GROUPS_ARR[@]} == 0)); then
  if [[ -n "${GROUPS:-}" ]]; then
    read -r -a GROUPS_ARR <<< "${GROUPS}"
  elif [[ -n "${ARGO_GROUPS:-}" ]]; then
    read -r -a GROUPS_ARR <<< "${ARGO_GROUPS}"
  fi
fi

[[ -n "${STAC_URL:-}" ]]    || { echo "[convert.sh] Missing --stac-url" >&2; exit 2; }
[[ -n "${OUTPUT_ZARR:-}" ]] || { echo "[convert.sh] Missing --output-zarr" >&2; exit 2; }

# Normalize
declare -a NORM_GROUPS=()
for g in "${GROUPS_ARR[@]:-}"; do
  [[ -z "$g" ]] && continue
  [[ "$g" == /* ]] && NORM_GROUPS+=("$g") || NORM_GROUPS+=("/$g")
done
if ((${#NORM_GROUPS[@]} == 0)) || { ((${#NORM_GROUPS[@]} == 1)) && [[ "${NORM_GROUPS[0]}" == "/0" ]]; }; then
  echo "[convert.sh] Error: group list is empty. Provide --groups <...> or set ARGO_GROUPS." >&2
  exit 5
fi

echo "[convert.sh] Parsed:"
echo "  STAC_URL=${STAC_URL}"
echo "  OUTPUT_ZARR=${OUTPUT_ZARR}"
echo "  GROUPS(${#NORM_GROUPS[@]}): ${NORM_GROUPS[*]}"
echo "  VALIDATE_GROUPS=${VALIDATE_GROUPS}"

# --- CLI sanity ---
if ! command -v eopf-geozarr >/dev/null 2>&1; then
  echo "[convert.sh] eopf-geozarr not on PATH" >&2
  python - <<'PY'
import os, sys, sysconfig
print("Python:", sys.version)
print("sys.executable:", sys.executable)
print("site:", sysconfig.get_paths())
print("PATH:", os.environ.get("PATH",""))
PY
  exit 127
fi
echo "[convert.sh] CLI version:"
eopf-geozarr --version || true

echo "[convert.sh] Probing input (info)..."
(eopf-geozarr info "${STAC_URL}" --verbose || true) | head -n 40 || true

# --- Preflight with JSON output for mapping ---
PF_JSON="/tmp/preflight.$RANDOM.json"
python - <<'PY' "${STAC_URL}" "${PF_JSON}" "${NORM_GROUPS[@]}"
import sys, json
url = sys.argv[1]; out = sys.argv[2]; req = sys.argv[3:]
result = {"available": [], "requested": req, "missing": [], "mapping": {}}
try:
    import fsspec
    fs, path = fsspec.core.url_to_fs(url)
    files = fs.find(path)
    avail = sorted({ '/' + f[len(path):].lstrip('/')[:-7] for f in files if f.endswith('.zgroup') })
    result["available"] = avail
    missing = [g for g in req if g not in avail]
    result["missing"] = missing
    # Build a simple unique-suffix mapping where possible
    for m in missing:
        tail = m.split('/')[-1]
        cands = [g for g in avail if g.endswith('/'+tail) or g == '/'+tail or g.endswith(m)]
        if len(cands) == 1:
            result["mapping"][m] = cands[0]
    with open(out, "w") as f:
        json.dump(result, f)
    if missing:
        print("[preflight] Available groups (first 60):", file=sys.stderr)
        for g in avail[:60]: print("  -", g, file=sys.stderr)
        print("[preflight] Missing:", missing, file=sys.stderr)
        print("[preflight] Auto-mapping candidates:", json.dumps(result["mapping"], indent=2), file=sys.stderr)
except Exception as e:
    # Do not fail open-listing errors
    print(f"[preflight] Warning: {e!r}; continuing...", file=sys.stderr)
    with open(out, "w") as f:
        json.dump(result, f)
PY

# Read mapping and possibly rewrite groups
if [[ -f "${PF_JSON}" ]]; then
  mapfile -t AVAIL < <(python - <<'PY' "${PF_JSON}" 'avail'
import sys, json; d=json.load(open(sys.argv[1]))
print("\n".join(d.get("available",[])))
PY
  ) || true
  MISSING_COUNT=$(python - <<'PY' "${PF_JSON}"
import sys, json; print(len(json.load(open(sys.argv[1])).get("missing",[])))
PY
  )
  if [[ "${MISSING_COUNT}" != "0" ]]; then
    # Attempt auto-map
    readarray -t NEW_GROUPS < <(python - <<'PY' "${PF_JSON}" "${NORM_GROUPS[@]}"
import sys, json
d=json.load(open(sys.argv[1])); req=sys.argv[2:]; mp=d.get("mapping",{})
out=[mp.get(g,g) for g in req]
print("\n".join(out))
PY
    ) || true
    if ((${#NEW_GROUPS[@]} > 0)); then
      echo "[convert.sh] Auto-mapped groups -> ${NEW_GROUPS[*]}"
      NORM_GROUPS=("${NEW_GROUPS[@]}")
    fi
    # If still missing and strict validation requested, bail
    STRICT=$(echo "${VALIDATE_GROUPS}" | tr '[:upper:]' '[:lower:]')
    if [[ "${STRICT}" == "true" ]]; then
      echo "[convert.sh] VALIDATE_GROUPS=true and one or more groups missing; aborting." >&2
      exit 8
    else
      echo "[convert.sh] Continuing despite missing groups (VALIDATE_GROUPS=false)." >&2
    fi
  fi
fi

# --- run conversion ---
set -x
eopf-geozarr convert "${STAC_URL}" "${OUTPUT_ZARR}" --groups "${NORM_GROUPS[@]}"
set +x

echo "[convert.sh] Done."
