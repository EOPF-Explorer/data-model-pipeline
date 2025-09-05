#!/usr/bin/env bash
set -euo pipefail

# Wrapper for the Argo Workflows CLI that targets a remote server using env vars.
# It normalizes server/namespace, attaches a token (from ARGO_TOKEN or .work/argo.token),
# and toggles TLS flags based on CLI feature detection.
#
# Usage:
#   scripts/argo_remote.sh <argo subcommand> [args]
#   scripts/argo_remote.sh submit ...
#   scripts/argo_remote.sh get @latest
#
# Help:
#   scripts/argo_remote.sh --help        # show Argo help for the wrapper
#   scripts/argo_remote.sh <subcmd> -h   # pass through to Argo help for subcmd
#
# Required env:
#   ARGO_REMOTE_SERVER   - URL or host[:port] of the Argo server (e.g. https://argo.example.com)
#   REMOTE_NAMESPACE     - target namespace/project (e.g. devseed)
#
# Optional env:
#   ARGO_AUTH_MODE       - e.g., sso (if supported by your Argo server)
#   ARGO_TLS_INSECURE    - 'true' to skip TLS verification (if supported)
#   ARGO_CA_FILE         - path to CA bundle (if supported)
#   ARGO_TOKEN           - Bearer token value (or set ARGO_TOKEN_FILE)
#   ARGO_TOKEN_FILE      - path to a file containing the token (default: .work/argo.token)

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: scripts/argo_remote.sh <argo subcommand> [args]

Environment:
  ARGO_REMOTE_SERVER   Required. URL or host[:port]
  REMOTE_NAMESPACE     Required. Namespace/project to operate in
  ARGO_TOKEN           Optional. Bearer token (or set ARGO_TOKEN_FILE)
  ARGO_TOKEN_FILE      Optional. Defaults to .work/argo.token
  ARGO_TLS_INSECURE    Optional. 'true' to skip TLS verification
  ARGO_CA_FILE         Optional. Path to CA bundle
  ARGO_AUTH_MODE       Optional. e.g. sso (feature-detected)

Examples:
  scripts/argo_remote.sh submit --from workflowtemplate/geozarr-convert -p image=...
  scripts/argo_remote.sh get @latest
USAGE
  exit 0
fi

# Dependency check early for clearer errors
if ! command -v argo >/dev/null 2>&1; then
  echo "ERROR: 'argo' CLI not found in PATH. Install Argo Workflows CLI." >&2
  exit 127
fi

# Feature-detect argo CLI flags
AUTH_FLAGS=()
TLS_FLAGS=()
if argo --help 2>/dev/null | grep -q -- '--insecure-skip-verify'; then
  if [[ "${ARGO_TLS_INSECURE:-}" == "true" ]]; then
    TLS_FLAGS+=("--insecure-skip-verify")
  fi
fi
if [[ -n "${ARGO_CA_FILE:-}" ]] && argo --help 2>/dev/null | grep -q -- '--certificate-authority'; then
  TLS_FLAGS+=("--certificate-authority" "${ARGO_CA_FILE}")
fi

# Normalize server and namespace (strip scheme, default to :443 if no port)
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

# Build environment for remote server (use HTTP/1 for compatibility)
ENV_ARGS=("ARGO_SERVER=${SERVER_ADDR}" "ARGO_HTTP1=true" "ARGO_SECURE=true" "KUBECONFIG=/dev/null")
if [[ "${ARGO_TLS_INSECURE:-}" == "true" ]]; then
  ENV_ARGS+=("ARGO_INSECURE_SKIP_VERIFY=true")
fi

# If ARGO_TOKEN or ARGO_TOKEN_FILE is provided, prefer token auth (avoids interactive login)
TOKEN_FLAGS=()
RAW_TOKEN="${ARGO_TOKEN:-}"
# Determine repo root (one level up from this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_TOKEN_FILE="${REPO_ROOT}/.work/argo.token"
if [[ -z "$RAW_TOKEN" && -n "${ARGO_TOKEN_FILE:-}" && -r "${ARGO_TOKEN_FILE}" ]]; then
  RAW_TOKEN=$(cat "${ARGO_TOKEN_FILE}")
fi
if [[ -z "$RAW_TOKEN" && -r "$DEFAULT_TOKEN_FILE" ]]; then
  RAW_TOKEN=$(cat "$DEFAULT_TOKEN_FILE")
fi
if [[ -n "$RAW_TOKEN" ]]; then
  # Normalize to a Bearer token for env; keep a stripped token for optional flags
  case "$RAW_TOKEN" in
    Bearer\ *) TOKEN_BEARER="$RAW_TOKEN" ;;
    *) TOKEN_BEARER="Bearer $RAW_TOKEN" ;;
  esac
  STRIPPED_TOKEN=${RAW_TOKEN#Bearer }
  # Export token via environment so different CLI versions pick it up
  ENV_ARGS+=("ARGO_TOKEN=${TOKEN_BEARER}")
  ENV_ARGS+=("ARGO_AUTH_TOKEN=${STRIPPED_TOKEN}")
  # Also add explicit flag when supported (best-effort)
  TOKEN_FLAG=""
  if argo --help 2>/dev/null | grep -q -- '--token '; then
    TOKEN_FLAG="--token"
  elif argo --help 2>/dev/null | grep -q -- '--auth-token'; then
    TOKEN_FLAG="--auth-token"
  fi
  if [[ -n "$TOKEN_FLAG" ]]; then
    TOKEN_FLAGS+=("$TOKEN_FLAG" "$STRIPPED_TOKEN")
  fi
fi

# Decide flags based on subcommand: avoid passing --auth-mode to 'login'
SUBCMD=${1:-}
EXTRA_AUTH_FLAGS=()
if [[ "$SUBCMD" != "login" ]]; then
  if [[ -n "${ARGO_AUTH_MODE:-}" ]] && argo --help 2>/dev/null | grep -q -- '--auth-mode'; then
    EXTRA_AUTH_FLAGS+=("--auth-mode" "${ARGO_AUTH_MODE}")
  fi
fi

# If after all this we still don't have a token in env or flags, warn loudly
if [[ -z "${TOKEN_BEARER:-}" ]] && [[ -z "${RAW_TOKEN:-}" ]] && [[ -z "${ARGO_TOKEN:-}" ]] && [[ -z "${ARGO_TOKEN_FILE:-}" ]]; then
  echo "ERROR: No token available for argo CLI (set ARGO_TOKEN or create .work/argo.token)" >&2
fi

# Safely expand arrays even when empty (avoid unbound errors under set -u)
exec env "${ENV_ARGS[@]}" argo \
  ${EXTRA_AUTH_FLAGS+"${EXTRA_AUTH_FLAGS[@]}"} \
  ${TLS_FLAGS+"${TLS_FLAGS[@]}"} \
  ${TOKEN_FLAGS+"${TOKEN_FLAGS[@]}"} \
  -n "${NS_TRIM}" "$@"
