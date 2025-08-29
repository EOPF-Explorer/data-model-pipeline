# Local prototype (k3d + Argo v3.6.5)

## Install tools (automatic)

If you're on **macOS (Homebrew)** or **Ubuntu/Debian**, run:

```bash
make bootstrap
```

This installs: Docker (macOS: cask), k3d, kubectl, argo CLI.

If you prefer manual setup, see below.

## Bring up the stack

```bash
# Create (or reuse) the local cluster
k3d cluster create k3s-default || true

# Build image, import into cluster, install Argo 3.6.5, ensure ns+PVC, apply template, submit
make up

# Stream logs
make logs
```

## Custom run

```bash
make submit \
  STAC_URL="https://your.host/path/in.zarr" \
  OUTPUT_ZARR="/data/out_geozarr.zarr" \
  GROUPS="measurements/reflectance/r20m" \
  VALIDATE_GROUPS=false
```

## Fetching outputs

The result lives in the PVC. Quick way to copy out via a transient pod:

```bash
# Name of the latest pod running your step
POD=$(make -s pod)

# Copy from the PVC-mounted path to your local machine
kubectl -n ${NAMESPACE:-argo} cp "$POD":/data/out_geozarr.zarr ./out_geozarr.zarr
```

## Manual installs (reference)

### macOS (Homebrew)

```bash
brew install k3d kubernetes-cli
brew install argoproj/tap/argo
brew install --cask docker
open -a Docker
```

### Ubuntu/Debian (apt + curl)

```bash
# Docker
sudo apt-get update && sudo apt-get install -y docker.io curl ca-certificates

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# kubectl (latest stable)
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# argo CLI
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.6.5/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv argo-linux-amd64 /usr/local/bin/argo
```

> If you’re on Windows, use WSL2 and follow the Ubuntu/Debian steps.
