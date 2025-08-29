#!/usr/bin/env bash
set -euo pipefail

# Usage: fix_kubeconfig.sh <cluster_name> <out_file>
CLUSTER_NAME="${1:-k3s-default}"
OUT_FILE="${2:-.work/kubeconfig}"

mkdir -p "$(dirname "$OUT_FILE")"

if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d not found; skipping kubeconfig generation." >&2
  exit 0
fi

# Try to get kubeconfig; if it fails, attempt a merge to regenerate
if ! k3d kubeconfig get "$CLUSTER_NAME" >/dev/null 2>&1; then
  k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context >/dev/null 2>&1 || true
fi

if k3d kubeconfig get "$CLUSTER_NAME" >/dev/null 2>&1; then
  k3d kubeconfig get "$CLUSTER_NAME" | sed -e 's/0\.0\.0\.0/127.0.0.1/g' > "$OUT_FILE"
  echo "Wrote kubeconfig to $OUT_FILE" >&2
else
  echo "Warning: could not obtain kubeconfig for cluster '$CLUSTER_NAME'." >&2
  # Create an empty file so env var can still be exported without error
  : > "$OUT_FILE"
fi
