#!/usr/bin/env bash
set -euo pipefail

# Create a long-lived token by submitting a bootstrap workflow that requests a service account token.
# The resulting token is stored at .work/argo.token and picked up automatically by argo_remote.sh.
#
# Usage:
#   scripts/bootstrap_argo_token.sh
#
# Config via env (sane defaults provided):
#   REMOTE_NAMESPACE   Namespace/project to create resources in (default: devseed)
#   SA_NAME            ServiceAccount name (default: dmclient)
#   ROLE_NAME          Role name bound to the ServiceAccount (default: dmclient)
#   SECRET_NAME        Secret name to store the token (default: dmclient.service-account-token)

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "${here}/.." && pwd)"

NS="${REMOTE_NAMESPACE:-devseed}"
SA_NAME="${SA_NAME:-dmclient}"
ROLE_NAME="${ROLE_NAME:-dmclient}"
SECRET_NAME="${SECRET_NAME:-dmclient.service-account-token}"
DURATION="${TOKEN_DURATION:-4320h}"

# Prefer kubectl path when no Argo token is available (avoids chicken-and-egg)
KCFG="${repo}/.work/kubeconfig"
if [[ -z "${ARGO_TOKEN:-}" && -z "${ARGO_TOKEN_FILE:-}" && ! -r "${repo}/.work/argo.token" && -r "$KCFG" ]]; then
  echo "[token] Using kubectl with ${KCFG} to mint a long-lived token..."
  export KUBECONFIG="$KCFG"
  # Apply minimal RBAC and SA
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NS}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${ROLE_NAME}
  namespace: ${NS}
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["workflows"]
    verbs: ["get","list","watch","create","update"]
  - apiGroups: [""]
    resources: ["pods","pods/log"]
    verbs: ["get","list","watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["serviceaccounts/token"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${ROLE_NAME}
  namespace: ${NS}
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: ${NS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${ROLE_NAME}
EOF

  # Mint token using TokenRequest API
  TOKEN_RAW=$(kubectl -n "$NS" create token "$SA_NAME" --duration="$DURATION")
  if [[ -z "$TOKEN_RAW" ]]; then
    echo "[token] ERROR: kubectl did not return a token" >&2; exit 3
  fi
  mkdir -p "${repo}/.work"
  printf 'Bearer %s' "$TOKEN_RAW" > "${repo}/.work/argo.token"
  echo "[token] Wrote token to ${repo}/.work/argo.token (via kubectl)"
  echo "[token] Next runs will pick it up automatically."
  exit 0
fi

echo "[token] Submitting bootstrap workflow (ns=${NS}, sa=${SA_NAME}, duration=${DURATION})..."
# Detect support for -o name
OUT_FLAG=""
if "${here}/argo_remote.sh" submit --help 2>/dev/null | grep -q -- '--output'; then
  OUT_FLAG=" -o name"
fi
WF_OUT=$("${here}/argo_remote.sh" submit \
  "${repo}/workflows/bootstrap-argo-token.yaml" \
  -p namespace="${NS}" \
  -p sa_name="${SA_NAME}" \
  -p role_name="${ROLE_NAME}" \
  -p secret_name="${SECRET_NAME}" \
  -p token_duration="${DURATION}"${OUT_FLAG} || true)

WF_NAME=$(printf '%s\n' "$WF_OUT" | awk '/^Name:[[:space:]]/{print $2; exit} /^name:[[:space:]]/{print $2; exit}')
[[ -n "$WF_NAME" ]] || WF_NAME=$(printf '%s\n' "$WF_OUT" | sed -n -E 's/.*Workflow[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*submitted.*/\1/ip' | head -n1)
[[ -n "$WF_NAME" ]] || WF_NAME=$(printf '%s\n' "$WF_OUT" | tail -n1)
if [[ -z "$WF_NAME" ]]; then
  echo "[token] ERROR: could not determine workflow name." >&2
  echo "[token] submit output was:" >&2
  printf '%s\n' "$WF_OUT" >&2
  echo "[token] If you do not have a token yet, ensure ${KCFG} exists and re-run; the script will use kubectl automatically." >&2
  exit 2
fi

# Guard: ensure we didn't accidentally capture another workflow name
if [[ "$WF_NAME" != bootstrap-argo-token-* ]]; then
  echo "[token] ERROR: unexpected workflow name '$WF_NAME' (expected prefix 'bootstrap-argo-token-')." >&2
  echo "[token] submit output was:" >&2
  printf '%s\n' "$WF_OUT" >&2
  exit 2
fi

echo "[token] Waiting for workflow ${WF_NAME} to complete..."
"${here}/argo_remote.sh" wait "$WF_NAME" >/dev/null

echo "[token] Reading token output..."
TOKEN=$("${here}/argo_remote.sh" get "$WF_NAME" -o jsonpath='{.status.outputs.parameters[?(@.name=="argo_token")].value}' || true)
if [[ -z "$TOKEN" ]]; then
  echo "[token] ERROR: no argo_token parameter found" >&2; exit 3
fi

mkdir -p "${repo}/.work"
echo "$TOKEN" > "${repo}/.work/argo.token"
echo "[token] Wrote token to ${repo}/.work/argo.token"
echo "[token] Next runs will pick it up automatically (via scripts/argo_remote.sh)"
