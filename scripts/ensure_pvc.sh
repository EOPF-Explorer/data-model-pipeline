#!/usr/bin/env bash
set -euo pipefail
ns="${1:-argo}"
pvc="${2:-geozarr-pvc}"

# Ensure namespace exists (idempotent)
if ! kubectl get namespace "${ns}" >/dev/null 2>&1; then
  echo "Namespace '${ns}' not found. Creating..."
  kubectl create namespace "${ns}"
else
  echo "Namespace '${ns}' exists."
fi

# Ensure PVC exists (idempotent)
if kubectl get pvc -n "${ns}" "${pvc}" >/dev/null 2>&1; then
  echo "PVC '${pvc}' already exists in namespace '${ns}'."
  exit 0
fi

cat <<YAML | kubectl apply -n "${ns}" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
YAML

echo "PVC '${pvc}' created in namespace '${ns}'."
