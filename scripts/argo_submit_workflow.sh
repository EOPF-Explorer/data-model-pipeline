#!/usr/bin/env bash
set -euo pipefail

# Submit from a WorkflowTemplate and print a clean UI link.
# Env: SUBMIT_IMAGE, REMOTE_SERVICE_ACCOUNT, PARAMS_FILE, ARGO_REMOTE_SERVER, REMOTE_NAMESPACE

here="$(cd "$(dirname "$0")" && pwd)"

SUBMIT_IMAGE="${SUBMIT_IMAGE:-}"
WF_TEMPLATE="${WF_TEMPLATE:-geozarr-convert}"
REMOTE_SERVICE_ACCOUNT="${REMOTE_SERVICE_ACCOUNT:-}"
PARAMS_FILE="${PARAMS_FILE:-params.json}"

[[ -n "${SUBMIT_IMAGE}" ]] || { echo "ERROR: SUBMIT_IMAGE not set" >&2; exit 2; }
[[ -f "${PARAMS_FILE}" ]] || { echo "ERROR: ${PARAMS_FILE} not found" >&2; exit 2; }

# Build params flags (only non-empty)
PARAMS=$(python3 "${here}/params_to_flags.py" "${PARAMS_FILE}")

# Some argo CLIs support -o name on submit; detect and enable when available.
OUT_FLAG=""
if "${here}/argo_remote.sh" submit --help 2>/dev/null | grep -q -- '--output'; then
  OUT_FLAG=" -o name"
fi

# Submit
WF_OUT=$("${here}/argo_remote.sh" submit \
  --serviceaccount "${REMOTE_SERVICE_ACCOUNT:-default}" \
  --from workflowtemplate/${WF_TEMPLATE} \
  -p image="${SUBMIT_IMAGE}" ${PARAMS}${OUT_FLAG} || true)

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

# Build UI URL
BASE=$(printf '%s' "${ARGO_REMOTE_SERVER:-}" | tr -d '[:space:]'); BASE="${BASE:-https://argo-workflows.hub-eopf-explorer.eox.at}"
BASE="${BASE%/}"
NS_TRIM=$(printf '%s' "${REMOTE_NAMESPACE:-default}" | tr -d '[:space:]')

if [[ -n "${WF_NAME}" ]]; then
  echo "Workflow: ${WF_NAME}"
  echo "Open: ${BASE}/workflows/${NS_TRIM}/${WF_NAME}"
else
  echo "Submitted. Open namespace: ${BASE}/workflows/${NS_TRIM}"
fi
