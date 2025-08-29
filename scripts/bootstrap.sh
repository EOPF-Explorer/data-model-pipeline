#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || return 0; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "==> Bootstrapping prerequisites (Docker, k3d, kubectl, argo)"
OS="$(uname -s || echo unknown)"

if ! have docker; then
  echo "Docker not found."
  if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "Installing Docker Desktop via Homebrew Cask..."
    brew install --cask docker || true
    echo "Please launch Docker.app manually the first time (open -a Docker)."
  elif [ -f /etc/debian_version ]; then
    echo "Installing docker.io via apt..."
    sudo apt-get update && sudo apt-get install -y docker.io
    sudo usermod -aG docker "$USER" || true
    echo "You may need to log out/in to use Docker without sudo."
  else
    echo "Please install Docker manually: https://docs.docker.com/engine/install/"
  fi
fi

if ! have k3d; then
  if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    brew install k3d
  else
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi
fi

if ! have kubectl; then
  if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    brew install kubernetes-cli
  else
    curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
  fi
fi

if ! have argo; then
  if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    brew install argoproj/tap/argo
  else
    curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.6.5/argo-linux-amd64.gz
    gunzip argo-linux-amd64.gz
    chmod +x argo-linux-amd64
    sudo mv argo-linux-amd64 /usr/local/bin/argo
  fi
fi

echo "==> Tools:"
docker --version || true
k3d version || true
kubectl version --client=true --output=yaml | grep gitVersion || true || true
argo version --short || true

echo "Bootstrap complete."
