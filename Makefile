# Portable, self-healing Makefile (no heredocs, no duplicate targets)

IMAGE ?= eopf-geozarr:dev
ARGO_VER ?= v3.6.5
ARGO_INSTALL_URL ?= https://github.com/argoproj/argo-workflows/releases/download/$(ARGO_VER)/install.yaml
NAMESPACE ?= argo
PVC_NAME ?= geozarr-pvc
PORTABLE_BUILD ?= 0
BASE_IMAGE ?= python:3.11-slim
RUNTIME_BASE_IMAGE ?= python:3.11-slim
DM_RAW_BASE ?= https://raw.githubusercontent.com/EOPF-Explorer/data-model
EOPF_GEOZARR_REF ?= main
EOPF_GEOZARR_SUBDIR ?=
BUILD_FLAGS ?=
CACHE_BUST := $(shell date +%s)
CLUSTER ?= k3s-default
REMOTE_PATH ?= /data
LOCAL_DIR ?= ./out
PYTHON ?= python3
PARAMS_FILE ?= params.json
ARGO_PROXY_PORT ?= 8081
K8S_PROXY_PORT ?= 8001
KUBECONFIG_FILE ?= .work/kubeconfig

# Export local kubeconfig so kubectl/argo consistently target the right API endpoint
export KUBECONFIG := $(abspath $(KUBECONFIG_FILE))

.PHONY: up up-fast up-rebuild build rebuild image-import ensure-pvc template apply submit logs logs-pod pod fetch status down env doctor validate
.PHONY: ui-reset-client ui-reset-server ui-proxy-bg ui-proxy-stop ui-diagnose

.PHONY: kubeconfig
kubeconfig:
	@bash scripts/fix_kubeconfig.sh $(CLUSTER) $(KUBECONFIG_FILE)

up: bootstrap cluster kubeconfig argo-install build image-import ensure-pvc template submit
	# full local run: bootstrap → cluster → argo → build → import → pvc → template → submit

up-fast: kubeconfig build image-import template submit

up-rebuild:
	$(MAKE) rebuild
	-$(MAKE) image-import
	$(MAKE) template
	$(MAKE) submit

build:
	# docker build eopf-geozarr:dev image
	@echo "Building image $(IMAGE) ..."
	docker build $(BUILD_FLAGS) \
	  --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	  --build-arg RUNTIME_BASE_IMAGE=$(RUNTIME_BASE_IMAGE) \
	  --build-arg PORTABLE_BUILD=$(PORTABLE_BUILD) \
	  --build-arg EOPF_GEOZARR_REF=$(EOPF_GEOZARR_REF) \
	  --build-arg EOPF_GEOZARR_SUBDIR=$(EOPF_GEOZARR_SUBDIR) \
	  --build-arg DM_RAW_BASE=$(DM_RAW_BASE) \
	  --build-arg CACHE_BUST=$(CACHE_BUST) \
	  -f docker/Dockerfile -t $(IMAGE) .

rebuild:
	$(MAKE) build BUILD_FLAGS="--no-cache --pull"

image-import:
	# import image into k3d cluster
	@if command -v k3d >/dev/null 2>&1; then \
	  echo "Importing image into k3d cluster..."; \
	  k3d image import --cluster $(CLUSTER) $(IMAGE) || true; \
	else \
	  true; \
	fi

ensure-pvc:
	# create namespace + pvc if not exists
	@bash scripts/ensure_pvc.sh $(NAMESPACE) $(PVC_NAME)

template: ensure-pvc
	# apply workflowtemplate to cluster
	@echo "Applying WorkflowTemplate..."
	kubectl apply -n $(NAMESPACE) -f workflows/geozarr-convert-template.yaml

apply: template

submit:
	# submit workflow run with parameters
	@[ -f $(PARAMS_FILE) ] || { echo "$(PARAMS_FILE) not found"; exit 2; }
	@$(MAKE) validate >/dev/null || true; \
	PARAMS=$$($(PYTHON) scripts/params_to_flags.py $(PARAMS_FILE)); \
	echo "argo submit -n $(NAMESPACE) --from workflowtemplate/geozarr-convert -p image=$(IMAGE) -p pvc_name=$(PVC_NAME) $$PARAMS"; \
	argo submit -n $(NAMESPACE) --from workflowtemplate/geozarr-convert -p image=$(IMAGE) -p pvc_name=$(PVC_NAME) $$PARAMS
	@$(MAKE) ui

pod:
	@kubectl get pods -n $(NAMESPACE) -l workflows.argoproj.io/workflow -o jsonpath='{.items[0].metadata.name}'; echo

logs:
	( argo logs -n $(NAMESPACE) @latest -c main -f || kubectl logs -n $(NAMESPACE) $$(make -s pod) -c main -f ) | sed -u 's/\r//g'

logs-pod:
	kubectl logs -n $(NAMESPACE) $$(make -s pod) -c main -f | sed -u 's/\r//g'

fetch:
	@echo "Fetching $(REMOTE_PATH) from latest pod → $(LOCAL_DIR) ..."
	mkdir -p $(LOCAL_DIR)
	P=$$(make -s pod); \
	kubectl cp $(NAMESPACE)/$$P:$(REMOTE_PATH) $(LOCAL_DIR) || \
	  bash scripts/fetch_from_pvc.sh $(NAMESPACE) $(PVC_NAME) $(REMOTE_PATH) $(LOCAL_DIR)

.PHONY: fetch-pvc
fetch-pvc:
	@echo "Fetching from PVC $(PVC_NAME) → $(LOCAL_DIR) ..."
	mkdir -p $(LOCAL_DIR)
	bash scripts/fetch_from_pvc.sh $(NAMESPACE) $(PVC_NAME) $(REMOTE_PATH) $(LOCAL_DIR)

status:
	@if [ -n "$(STATUS)" ]; then \
	  argo list -n $(NAMESPACE) --status $(STATUS); \
	else \
	  argo list -n $(NAMESPACE); \
	fi

env:
	@echo IMAGE=$(IMAGE)
	@echo NAMESPACE=$(NAMESPACE)
	@echo PVC_NAME=$(PVC_NAME)
	@echo PORTABLE_BUILD=$(PORTABLE_BUILD)
	@echo BASE_IMAGE=$(BASE_IMAGE)
	@echo RUNTIME_BASE_IMAGE=$(RUNTIME_BASE_IMAGE)
	@echo EOPF_GEOZARR_REF=$(EOPF_GEOZARR_REF)
	@echo EOPF_GEOZARR_SUBDIR=$(EOPF_GEOZARR_SUBDIR)
	@echo DM_RAW_BASE=$(DM_RAW_BASE)

down:
	-argo delete -n $(NAMESPACE) --all || true
	-kubectl delete -n $(NAMESPACE) workflowtemplate geozarr-convert || true
	-kubectl delete -n $(NAMESPACE) pvc $(PVC_NAME) || true

doctor:
	@echo "Docker:    $$(docker --version 2>/dev/null || echo missing)"
	@echo "kubectl:   $$(kubectl version --client=true --short 2>/dev/null || echo missing)"
	@echo "argo:      $$(argo version --short 2>/dev/null || echo missing)"
	@echo "k3d:       $$(k3d version 2>/dev/null || echo 'not installed (ok)')"
	@echo "jq:        $$(jq --version 2>/dev/null || echo 'optional (we use Python)')"

.PHONY: argo-install
argo-install: kubeconfig
	# install argo workflows CRDs + controller (pinned v3.6.5)
	@echo "Installing Argo Workflows $(ARGO_VER) into namespace $(NAMESPACE)..."
	@kubectl get namespace $(NAMESPACE) >/dev/null 2>&1 || kubectl create namespace $(NAMESPACE)
	kubectl apply -n $(NAMESPACE) -f $(ARGO_INSTALL_URL)
	@echo "Waiting for Argo controller and server to become ready..."
	kubectl -n $(NAMESPACE) rollout status deploy/workflow-controller
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server
	@echo "Verifying CRDs..."
	kubectl api-resources | grep -q WorkflowTemplate && echo "CRDs present." || (echo "CRDs missing!"; exit 1)
	@echo "Ensuring local UI dev ServiceAccount bound to admin (optional)..."
	@bash scripts/ensure_ui_access.sh $(NAMESPACE) || true
.PHONY: help
help:
	@echo ""
	@echo "Targets:"
	@echo "  bootstrap     Install Docker (where supported), k3d, kubectl, argo CLI."
	@echo "  up            Install Argo v$(ARGO_VER), build, import image, ensure ns+PVC, apply template, submit."
	@echo "                Tip: Ensure Docker Desktop is running before 'make up'."
	@echo "  build         Build the container image ($(IMAGE))."
	@echo "  image-import  Import the image into the k3d cluster."
	@echo "  ensure-pvc    Ensure namespace and PVC exist (idempotent)."
	@echo "  template      Apply WorkflowTemplate."
	@echo "  submit        Submit a run from the WorkflowTemplate."
	@echo "  logs          Tail logs for the latest workflow."
	@echo "  get-output    Copy from /data in latest pod: OUTPUT_PATH, LOCAL_PATH"
	@echo "  fetch         Copy REMOTE_PATH from PVC via helper pod to LOCAL_DIR"
	@echo "  pod           Print the name of the latest pod."
	@echo "  down          Delete Argo objects (namespace kept)"
	@echo "  doctor        Print versions of tools."
	@echo ""
	@echo "UI shortcuts:"
	@echo "  ui              Show progress and print the Argo UI proxy link"
	@echo "  ui-open         Start/reuse local HTTP proxy and open the Argo UI"
	@echo "  ui-mode-server  Switch argo-server to server (no-login) mode"
	@echo "  ui-mode-client  Switch argo-server to client (token-based) mode"
	@echo "  ui-proxy-bg     (Optional) Start local auth-injecting HTTP proxy"
	@echo "  ui-proxy-stop   Stop the local auth-injecting proxy"
	@echo "  ui-reset-client Force client mode and open the proxy link"
	@echo "  ui-reset-server Force server mode and open the proxy link"
	@echo ""
	@echo "Useful vars (override as needed):"
	@echo "  NAMESPACE=argo PVC_NAME=geozarr-pvc IMAGE=eopf-geozarr:dev ARGO_VER=v3.6.5"
	@echo ""
	@echo "Maintenance:"
	@echo "  cluster-delete Delete the k3d cluster if it exists (use after partial/failed creates)."

.PHONY: docker-wait bootstrap
docker-wait:
	# Wait for Docker daemon to be ready (macOS Docker Desktop can take a while)
	@SECS=$${DOCKER_WAIT_SECS:-120}; \
	for i in $$(seq 1 $$SECS); do \
	  if docker version >/dev/null 2>&1; then \
	    echo "Docker is ready."; \
	    exit 0; \
	  fi; \
	  if [ $$i -eq $$SECS ]; then \
	    echo "Docker is not ready after $$SECS seconds."; \
	    echo "Tip: On macOS, open Docker Desktop and wait until it shows \"Running\"."; \
	    exit 1; \
	  fi; \
	  sleep 1; \
	done

bootstrap:
	# install/check docker, k3d, kubectl, argo CLI
	@scripts/bootstrap.sh
.PHONY: cluster
cluster: docker-wait
	# ensure k3d cluster exists (create if missing)
	@echo "Ensuring k3d cluster $(CLUSTER) exists..."
	@if ! k3d cluster list | awk 'NR>1 {print $$1}' | grep -qx "$(CLUSTER)"; then \
		echo "Creating cluster $(CLUSTER)..."; \
		if ! k3d cluster create $(CLUSTER); then \
		  echo "\nERROR: Failed to create k3d cluster. This is often caused by a Docker Engine issue (e.g. Internal Server Error 500)."; \
		  echo "Troubleshooting steps:"; \
		  echo "  1) Ensure Docker Desktop is running and healthy (Docker Desktop -> Running)."; \
		  echo "  2) In a terminal, run: docker version && docker ps"; \
		  echo "  3) If errors persist, Restart Docker Desktop (Docker Desktop -> Quit, then reopen)."; \
		  echo "  4) If a partial cluster exists, try: make cluster-delete and re-run make up."; \
		  exit 2; \
		fi; \
	else \
		echo "Cluster $(CLUSTER) already exists."; \
	fi

.PHONY: cluster-delete
cluster-delete: docker-wait
	# delete the k3d cluster if it exists (useful after partial/failed creates)
	@echo "Deleting k3d cluster $(CLUSTER) if it exists..."
	@k3d cluster list | awk 'NR>1 {print $$1}' | grep -qx "$(CLUSTER)" \
	  && k3d cluster delete $(CLUSTER) \
	  || echo "No existing cluster named $(CLUSTER)."
.PHONY: get-output
# Copy a result file/folder from the latest pod's /data to local path.
# Usage: make get-output OUTPUT_PATH=/data/out.zarr LOCAL_PATH=./out.zarr
get-output:
	@[ -n "$(OUTPUT_PATH)" ] || (echo "Set OUTPUT_PATH=/data/..." && exit 1)
	@[ -n "$(LOCAL_PATH)" ] || (echo "Set LOCAL_PATH=./..." && exit 1)
	@POD=$$(make -s pod); \
	  echo "Copying from $$POD:$(OUTPUT_PATH) -> $(LOCAL_PATH)"; \
	  kubectl -n $(NAMESPACE) cp "$$POD:$(OUTPUT_PATH)" "$(LOCAL_PATH)"

.PHONY: ui
ui:
	@(argo -n $(NAMESPACE) logs @latest -c main -f || argo -n $(NAMESPACE) logs @latest -f) | $(PYTHON) scripts/progress_ui.py

.PHONY: ui-open
ui-open:
	@$(PYTHON) scripts/print_ui_link.py -n $(NAMESPACE) --open

.PHONY: ui-mode-server
ui-mode-server:
	@echo "Switching argo-server auth mode to 'server' (no-login local dashboard)..."
	@ARGO_SET_SECURE=false $(PYTHON) scripts/argo_set_auth_mode.py --namespace $(NAMESPACE) --mode server
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server
	@echo "Done. Use 'make ui-open' to open the local proxy URL (no token required)."

.PHONY: ui-mode-client
ui-mode-client:
	@echo "Switching argo-server auth mode to 'client' (default token-based)..."
	@ARGO_SET_SECURE=true $(PYTHON) scripts/argo_set_auth_mode.py --namespace $(NAMESPACE) --mode client
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server
	@echo "Done. Use 'make ui-open' to open the local proxy URL."

# Start auth-injecting local HTTP proxy (optional)
.PHONY: ui-proxy-bg
ui-proxy-bg:
	@mkdir -p .work
	@echo "Starting auth-injecting Argo UI proxy on http://127.0.0.1:$(ARGO_PROXY_PORT) ..."
	@nohup $(PYTHON) scripts/argo_ui_proxy.py --namespace $(NAMESPACE) --port $(ARGO_PROXY_PORT) >/dev/null 2>&1 & echo $$! > .work/argo_ui_proxy.pid
	@echo "http://127.0.0.1:$(ARGO_PROXY_PORT)" > .work/argo_ui_proxy.port
	@echo "Argo UI proxy at http://127.0.0.1:$(ARGO_PROXY_PORT) (Authorization header injected)."

.PHONY: ui-proxy-stop
ui-proxy-stop:
	@if [ -f .work/argo_ui_proxy.pid ]; then \
	  PID=$$(cat .work/argo_ui_proxy.pid); \
	  echo "Stopping Argo UI proxy (pid $$PID)..."; \
	  kill $$PID || true; \
	  rm -f .work/argo_ui_proxy.pid .work/argo_ui_proxy.port; \
	else \
	  echo "No Argo UI proxy pidfile found."; \
	fi

# One-shot recovery helpers for common blank/unauthorized UI issues
.PHONY: ui-reset-client
ui-reset-client: ui-proxy-stop
	@echo "Setting argo-server to client auth mode with secure HTTPS..."
	@ARGO_SET_SECURE=true $(PYTHON) scripts/argo_set_auth_mode.py --namespace $(NAMESPACE) --mode client
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server
	@$(PYTHON) scripts/print_ui_link.py -n $(NAMESPACE) --open

.PHONY: ui-reset-server
ui-reset-server: ui-proxy-stop
	@echo "Setting argo-server to server auth mode (no login, http)..."
	@ARGO_SET_SECURE=false $(PYTHON) scripts/argo_set_auth_mode.py --namespace $(NAMESPACE) --mode server
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server
	@$(PYTHON) scripts/print_ui_link.py -n $(NAMESPACE) --open


.PHONY: validate
validate:
	@$(PYTHON) scripts/validate_groups.py $(PARAMS_FILE) || true