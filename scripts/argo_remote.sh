#!/usr/bin/env bash
set -euo pipefail

# Run argo CLI against a remote Argo Workflows server via env vars.
# Env:
#   ARGO_REMOTE_SERVER   - URL or host[:port]
#   REMOTE_NAMESPACE     - target namespace
#   ARGO_AUTH_MODE       - e.g., sso (if supported)
#   ARGO_TLS_INSECURE    - 'true' to skip TLS verification (if supported)
#   ARGO_CA_FILE         - path to CA bundle (if supported)

# Feature-detect argo CLI flags
AUTH_FLAGS=()
TLS_FLAGS=()
if argo --help 2>/dev/null | grep -q -- '--auth-mode'; then
  AUTH_FLAGS+=("--auth-mode" "${ARGO_AUTH_MODE:-sso}")
fi
if argo --help 2>/dev/null | grep -q -- '--insecure-skip-verify'; then
  if [[ "${ARGO_TLS_INSECURE:-}" == "true" ]]; then
    TLS_FLAGS+=("--insecure-skip-verify")
  fi
fi
if [[ -n "${ARGO_CA_FILE:-}" ]] && argo --help 2>/dev/null | grep -q -- '--certificate-authority'; then
  TLS_FLAGS+=("--certificate-authority" "${ARGO_CA_FILE}")
fi

# Normalize server and namespace
SERVER_ADDR=$(printf '%s' "${ARGO_REMOTE_SERVER:-}" | sed -E 's#^https?://##' | tr -d '[:space:]')
if [[ -z "$SERVER_ADDR" ]]; then
  echo "ERROR: ARGO_REMOTE_SERVER not set" >&2
  exit 2
fi
case "$SERVER_ADDR" in
  *:*) ;;
  *) SERVER_ADDR="${SERVER_ADDR}:443" ;;
esac
NS_TRIM=$(printf '%s' "${REMOTE_NAMESPACE:-default}" | tr -d '[:space:]')

# Build environment for remote server
ENV_ARGS=("ARGO_SERVER=${SERVER_ADDR}" "ARGO_HTTP1=true" "ARGO_SECURE=true" "KUBECONFIG=/dev/null")
if [[ "${ARGO_TLS_INSECURE:-}" == "true" ]]; then
  ENV_ARGS+=("ARGO_INSECURE_SKIP_VERIFY=true")
fi

# Safely expand arrays even when empty (avoid unbound errors under set -u)
exec env "${ENV_ARGS[@]}" argo \
  ${AUTH_FLAGS+"${AUTH_FLAGS[@]}"} \
  ${TLS_FLAGS+"${TLS_FLAGS[@]}"} \
  -n "${NS_TRIM}" "$@"
