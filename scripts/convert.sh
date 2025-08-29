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
import sys
import json


def build_preflight(url, req):
  result = {"available": [], "requested": req, "missing": [], "mapping": {}}
  try:
    import fsspec
    fs, path = fsspec.core.url_to_fs(url)
    files = fs.find(path)
    avail = []
    for f in files:
      if f.endswith(".zgroup"):
        rel = f[len(path):].lstrip("/")
        rel = "/" + rel[:-7]
        avail.append(rel)
    avail = sorted(set(avail))
    # Fallback for endpoints that don't support listing: probe requested groups directly
    if not avail and req:
      try:
        for g in req:
          gp = path.rstrip("/") + "/" + g.lstrip("/") + "/.zgroup"
          if fs.exists(gp):
            avail.append(g if g.startswith("/") else "/" + g)
      except Exception:
        pass
    result["available"] = avail
    missing = [g for g in req if g not in avail]
    result["missing"] = missing
    # Build a simple unique-suffix mapping where possible
    for m in missing:
      tail = m.split("/")[-1]
      cands = [g for g in avail if g.endswith("/" + tail) or g == "/" + tail or g.endswith(m)]
      if len(cands) == 1:
        result["mapping"][m] = cands[0]
  except Exception as e:
    # Do not fail open-listing errors
    print(f"[preflight] Warning: {e!r}; continuing...", file=sys.stderr)
  return result


if __name__ == "__main__":
  url = sys.argv[1]
  out = sys.argv[2]
  req = sys.argv[3:]
  res = build_preflight(url, req)
  try:
    with open(out, "w") as f:
      json.dump(res, f)
  except Exception:
    pass
  if res.get("missing"):
    print("[preflight] Available groups (first 60):", file=sys.stderr)
    for g in res.get("available", [])[:60]:
      print("  -", g, file=sys.stderr)
    print("[preflight] Missing:", res["missing"], file=sys.stderr)
    print(
      "[preflight] Auto-mapping candidates:", json.dumps(res.get("mapping", {}), indent=2), file=sys.stderr
    )
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
      OLD_JOIN="${NORM_GROUPS[*]}"; NEW_JOIN="${NEW_GROUPS[*]}"
      if [[ "${NEW_JOIN}" != "${OLD_JOIN}" ]]; then
        echo "[convert.sh] Auto-mapped groups -> ${NEW_GROUPS[*]}"
      fi
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

# --- run conversion with resilient retries ---
# Tweakable via env:
#   MAX_ATTEMPTS: total tries (default 6)
#   BACKOFF_INITIAL: first backoff seconds (default 2)
#   BACKOFF_MULTIPLIER: exponential base (default 2)
#   BACKOFF_MAX: cap per-sleep seconds (default 60)
MAX_ATTEMPTS=${MAX_ATTEMPTS:-6}
BACKOFF_INITIAL=${BACKOFF_INITIAL:-2}
BACKOFF_MULTIPLIER=${BACKOFF_MULTIPLIER:-2}
BACKOFF_MAX=${BACKOFF_MAX:-60}

LOG_FILE="/tmp/convert.$RANDOM.log"
attempt=1
last_ec=0

should_retry() {
  # Inspect log for transient network/server disconnect patterns
  # Lowercase match to broaden coverage
  tr '[:upper:]' '[:lower:]' <"$LOG_FILE" | grep -E -q \
    "server disconnected|connection reset|read timed out|temporary|temporarily|eof|rst|connection.*closed|broken pipe|stream error|upstream error|502|503|504|network is unreachable|timed out|tls: handshake failure"
}

calc_backoff() {
  # attempt starts at 1
  local n=$((attempt-1))
  local delay=$BACKOFF_INITIAL
  # integer exponentiation loop (bash portable)
  for _ in $(seq 1 $n); do
    delay=$((delay * BACKOFF_MULTIPLIER))
    [ $delay -gt $BACKOFF_MAX ] && { delay=$BACKOFF_MAX; break; }
  done
  # jitter 0..delay/4
  local jitter=$((RANDOM % (delay/4 + 1)))
  echo $((delay + jitter))
}

echo "[convert.sh] Starting conversion with up to ${MAX_ATTEMPTS} attempt(s)..."
while (( attempt <= MAX_ATTEMPTS )); do
  echo "[convert.sh] Attempt ${attempt}/${MAX_ATTEMPTS}"
  : >"$LOG_FILE"
  set -x
  # capture exit of eopf-geozarr, not tee
  eopf-geozarr convert "${STAC_URL}" "${OUTPUT_ZARR}" --groups "${NORM_GROUPS[@]}" 2>&1 | tee -a "$LOG_FILE"
  last_ec=${PIPESTATUS[0]}
  set +x
  if [[ $last_ec -eq 0 ]]; then
    echo "[convert.sh] Conversion succeeded on attempt ${attempt}."
    echo "[convert.sh] Done."
    exit 0
  fi
  # Check if transient and we have retries left
  if should_retry && (( attempt < MAX_ATTEMPTS )); then
    sleep_s=$(calc_backoff)
    echo "[convert.sh] Transient failure detected (e=${last_ec}). Will retry after ${sleep_s}s..."
    # Show a short tail for context
    tail -n 20 "$LOG_FILE" >&2 || true
    sleep "$sleep_s"
    attempt=$((attempt+1))
    continue
  else
    echo "[convert.sh] Non-retriable failure or attempts exhausted (e=${last_ec})."
    tail -n 50 "$LOG_FILE" >&2 || true
    exit $last_ec
  fi
done

echo "[convert.sh] Exhausted retries without success (last exit=${last_ec})." >&2
exit ${last_ec:-1}
