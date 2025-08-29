#!/usr/bin/env bash
set -euo pipefail
NS="${1:-argo}"
echo "[ensure_ui_access] Namespace: $NS"

kubectl -n "$NS" create sa argo-ui-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create rolebinding argo-ui-admin \
  --clusterrole=admin \
  --serviceaccount="$NS":argo-ui-dev \
  --dry-run=client -o yaml | kubectl apply -f -

# Grant cluster-admin for frictionless local UI (includes access to cluster-scoped templates)
kubectl create clusterrolebinding argo-ui-dev-cluster-admin \
  --clusterrole=cluster-admin \
  --serviceaccount="$NS":argo-ui-dev \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[ensure_ui_access] ServiceAccount 'argo-ui-dev' ready with admin permissions."
