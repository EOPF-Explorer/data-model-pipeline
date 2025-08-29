#!/usr/bin/env bash
set -euo pipefail

# Usage: fetch_from_pvc.sh <namespace> <pvc_name> <remote_path> <local_dir>
NS="${1:-argo}"
PVC="${2:-geozarr-pvc}"
REMOTE="${3:-/data}"
LOCAL_DIR="${4:-./out}"

# Create a short-lived helper pod that mounts the PVC at /data and sleeps
POD_NAME="fetch-pvc-$(date +%s)-$RANDOM"

# Trim trailing slashes
REMOTE=${REMOTE%/}
LOCAL_DIR=${LOCAL_DIR%/}

cat <<YAML | kubectl -n "$NS" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  labels:
    app: pvc-fetch
spec:
  restartPolicy: Never
  containers:
  - name: fetch
    image: busybox:1.36
    command: ["sh","-c","sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${PVC}
YAML

# Wait for the pod to be Ready (or at least Running)
echo "Waiting for helper pod ${POD_NAME} to be Running..."
kubectl -n "$NS" wait --for=condition=Ready pod/"$POD_NAME" --timeout=60s >/dev/null 2>&1 || \
  kubectl -n "$NS" wait --for=condition=ContainersReady pod/"$POD_NAME" --timeout=60s >/dev/null 2>&1 || true

# Copy from the mounted PVC path to local
SRC_PATH="${POD_NAME}:${REMOTE}"
mkdir -p "$LOCAL_DIR"
echo "Copying $SRC_PATH -> $LOCAL_DIR"
if ! kubectl -n "$NS" cp "$SRC_PATH" "$LOCAL_DIR"; then
  echo "kubectl cp failed; attempting tar stream..."
  kubectl -n "$NS" exec "$POD_NAME" -- sh -c "cd / && tar cf - ${REMOTE#/}" | tar xvf - -C "$LOCAL_DIR"
fi

# Cleanup helper pod
echo "Cleaning up helper pod ${POD_NAME}"
kubectl -n "$NS" delete pod "$POD_NAME" --wait=false >/dev/null 2>&1 || true

echo "Fetch complete: ${LOCAL_DIR}"
