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

.PHONY: up up-fast up-rebuild build rebuild image-import ensure-pvc template apply submit logs logs-pod pod fetch status down env doctor

up: bootstrap cluster argo-install build image-import ensure-pvc template submit
	# full local run: bootstrap → cluster → argo → build → import → pvc → template → submit

up-fast: build image-import template submit

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
	  k3d image import --cluster k3s-default $(IMAGE) || true; \
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
	@[ -f params.json ] || { echo "params.json not found"; exit 2; }
	@PARAMS=$$(python scripts/params_to_flags.py params.json); \
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
	@echo "Fetching /data from latest pod → ./out ..."
	mkdir -p out
	P=$$(make -s pod); \
	kubectl cp $(NAMESPACE)/$$P:/data ./out || true

status:
	argo list -n $(NAMESPACE) --status

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
argo-install:
	# install argo workflows CRDs + controller (pinned v3.6.5)
	@echo "Installing Argo Workflows $(ARGO_VER) into namespace $(NAMESPACE)..."
	@kubectl get namespace $(NAMESPACE) >/dev/null 2>&1 || kubectl create namespace $(NAMESPACE)
	kubectl apply -n $(NAMESPACE) -f $(ARGO_INSTALL_URL)
	@echo "Waiting for Argo controller and server to become ready..."
	kubectl -n $(NAMESPACE) rollout status deploy/workflow-controller
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server
	@echo "Verifying CRDs..."
	kubectl api-resources | grep -q WorkflowTemplate && echo "CRDs present." || (echo "CRDs missing!"; exit 1)
.PHONY: help
help:
	@echo ""
	@echo "Targets:"
	@echo "  bootstrap     Install Docker (where supported), k3d, kubectl, argo CLI."
	@echo "  up            Install Argo v$(ARGO_VER), build, import image, ensure ns+PVC, apply template, submit."
	@echo "  build         Build the container image ($(IMAGE))."
	@echo "  image-import  Import the image into the k3d cluster."
	@echo "  ensure-pvc    Ensure namespace and PVC exist (idempotent)."
	@echo "  template      Apply WorkflowTemplate."
	@echo "  submit        Submit a run from the WorkflowTemplate."
	@echo "  logs          Tail logs for the latest workflow.
	@echo "  get-output    Copy from /data in latest pod: OUTPUT_PATH, LOCAL_PATH"
	@echo "  fetch         Copy REMOTE_PATH from PVC via helper pod to LOCAL_DIR""
	@echo "  pod           Print the name of the latest pod."
	@echo "  down          Delete Argo objects (namespace kept)"
	@echo "  doctor        Print versions of tools."
	@echo ""
	@echo "Useful vars (override as needed):"
	@echo "  NAMESPACE=argo PVC_NAME=geozarr-pvc IMAGE=eopf-geozarr:dev ARGO_VER=v3.6.5"
	@echo ""

.PHONY: bootstrap
bootstrap:
	# install/check docker, k3d, kubectl, argo CLI
	@scripts/bootstrap.sh
.PHONY: cluster
cluster:
	# ensure k3d cluster exists (create if missing)
	@echo "Ensuring k3d cluster $(CLUSTER) exists..."
	@if ! k3d cluster list | awk 'NR>1 {print $$1}' | grep -qx "$(CLUSTER)"; then \
		echo "Creating cluster $(CLUSTER)..."; \
		k3d cluster create $(CLUSTER); \
	else \
		echo "Cluster $(CLUSTER) already exists."; \
	fi
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
	@(argo -n $(NAMESPACE) logs @latest -c main -f || argo -n $(NAMESPACE) logs @latest -f) | python3 scripts/progress_ui.py