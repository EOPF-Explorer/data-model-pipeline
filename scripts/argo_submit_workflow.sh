#!/usr/bin/env bash
set -euo pipefail

# Quietly submit a workflow from the WorkflowTemplate and print a clean URL.
# Reads configuration from environment variables:
#   SUBMIT_IMAGE, REMOTE_SERVICE_ACCOUNT, PARAMS_FILE,
#   ARGO_REMOTE_SERVER, REMOTE_NAMESPACE

here="$(cd "$(dirname "$0")" && pwd)"

SUBMIT_IMAGE="${SUBMIT_IMAGE:-}"
WF_TEMPLATE="${WF_TEMPLATE:-geozarr-convert}"
REMOTE_SERVICE_ACCOUNT="${REMOTE_SERVICE_ACCOUNT:-${REMOTE_SERVICE_ACCOUNT:-}}"
PARAMS_FILE="${PARAMS_FILE:-params.json}"

if [[ -z "${SUBMIT_IMAGE}" ]]; then
  echo "ERROR: SUBMIT_IMAGE not set" >&2
  exit 2
fi
if [[ ! -f "${PARAMS_FILE}" ]]; then
  echo "ERROR: ${PARAMS_FILE} not found" >&2
  exit 2
fi

# Build params flags
PARAMS=$(python3 "${here}/params_to_flags.py" "${PARAMS_FILE}")

# Detect output flag support
OUT_FLAG=""
if "${here}/argo_remote.sh" submit --help 2>/dev/null | grep -q -- '--output'; then
  OUT_FLAG=" -o name"
fi

# Submit
EXTRA_PARAMS=()

WF_OUT=$("${here}/argo_remote.sh" submit \
  --serviceaccount "${REMOTE_SERVICE_ACCOUNT:-default}" \
  --from workflowtemplate/${WF_TEMPLATE} \
  -p image="${SUBMIT_IMAGE}" ${EXTRA_PARAMS:+${EXTRA_PARAMS[@]}} ${PARAMS}${OUT_FLAG} || true)

# Parse workflow name across CLI versions
WF_NAME=$(printf '%s\n' "${WF_OUT}" | awk '/^Name:[[:space:]]/{print $2; exit} /^name:[[:space:]]/{print $2; exit}')
if [[ -z "${WF_NAME}" ]]; then
  WF_NAME=$(printf '%s\n' "${WF_OUT}" | sed -n -E 's/.*Workflow[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*submitted.*/\1/ip' | head -n1)
fi
if [[ -z "${WF_NAME}" && -n "${OUT_FLAG}" ]]; then
  WF_NAME=$(printf '%s\n' "${WF_OUT}" | tail -n1)
fi
if [[ -z "${WF_NAME}" ]]; then
  WF_NAME=$("${here}/argo_remote.sh" get @latest 2>/dev/null | awk '/^Name:[[:space:]]/{print $2; exit}')
fi

# Build URLs
BASE=$(printf '%s' "${ARGO_REMOTE_SERVER:-}" | tr -d '[:space:]')
if [[ -z "${BASE}" ]]; then
  BASE="https://argo-workflows.hub-eopf-explorer.eox.at"
fi
BASE="${BASE%/}"
NS_TRIM=$(printf '%s' "${REMOTE_NAMESPACE:-default}" | tr -d '[:space:]')

if [[ -n "${WF_NAME}" ]]; then
  echo "Workflow: ${WF_NAME}"
  echo "Open: ${BASE}/workflows/${NS_TRIM}/${WF_NAME}"
else
  echo "Submitted. Open namespace: ${BASE}/workflows/${NS_TRIM}"
fi
