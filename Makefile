
# ===== User-configurable defaults =====
IMAGE_REG ?= data-model-pipeline
TAG       ?= dev
REF       ?= main
SUBDIR    ?=
PORTABLE  ?=
NAMESPACE ?= argo
CLUSTER   ?= k3s-default

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
  PLATFORM ?= linux/arm64
else ifeq ($(HOST_ARCH),aarch64)
  PLATFORM ?= linux/arm64
else
  PLATFORM ?= linux/amd64
endif
ifeq ($(PLATFORM),linux/arm64)
  PORTABLE ?= 1
endif

DOCKERFILE ?= $(shell [ -f docker/Dockerfile ] && echo docker/Dockerfile || echo Dockerfile)

STAMP      := $(shell date -u +%Y%m%d%H%M%S)
IMMUTABLE  ?= 0   # stable tags by default; override with IMMUTABLE=1 in CI
NC         ?= 0   # use cached layers unless forced
PULL       ?= 0   # don’t pull unless forced

IMAGE_BASE := $(IMAGE_REG):$(TAG)
ifeq ($(IMMUTABLE),1)
  IMAGE := $(IMAGE_REG):$(TAG)-$(STAMP)
else
  IMAGE := $(IMAGE_BASE)
endif

ifneq (,$(findstring /,$(IMAGE)))
  PULLPOL := Always
else
  PULLPOL := IfNotPresent
endif

TPL       ?= workflows/geozarr-convert-template.yaml
PARAMS    ?= params.json
WORKDIR   ?= .work

STAC_URL    ?=
OUTPUT_ZARR ?=
ZARR_GROUPS ?=
DEFAULT_PULLPOL := $(if $(findstring /,$(IMAGE)),Always,IfNotPresent)
PULLPOL ?= $(DEFAULT_PULLPOL)

LOAD_STRATEGY ?= auto

.PHONY: help build push load load-k3d load-minikube build-in-minikube \
        argo-install template apply dev submit submit-cli submit-api status \
        latest logs-save clean _ensure-dirs fetch-tar run clean-pvc \
        print-config print-image

help:
	@echo "Targets:"
	@echo "  build            Build image (PORTABLE=1 for system GDAL/PROJ)."
	@echo "  load             Auto-load into k3d/minikube (or push, if configured)."
	@echo "  apply            Build + load + install Argo + template."
	@echo "  dev              Build + load + template (fast local loop)."
	@echo "  submit           Submit workflow with params.json or env overrides."
	@echo "  submit-cli       CLI submission shortcut."
	@echo "  submit-api       API submission shortcut."
	@echo "  status           Show workflow status."
	@echo "  fetch-tar        Fetch results from PVC."

print-config:
	@echo "IMAGE_BASE = $(IMAGE_BASE)"
	@echo "IMAGE      = $(IMAGE)"
	@echo "PULLPOL    = $(PULLPOL)"
	@echo "IMMUTABLE  = $(IMMUTABLE)"
	@echo "REF        = $(REF)"
	@echo "SUBDIR     = $(SUBDIR)"
	@echo "PORTABLE   = $(PORTABLE)"
	@echo "PLATFORM   = $(PLATFORM)"
	@echo "DOCKERFILE = $(DOCKERFILE)"
	@echo "NAMESPACE  = $(NAMESPACE)"
	@echo "CLUSTER    = $(CLUSTER)"
	@echo "TPL        = $(TPL)"
	@echo "PARAMS     = $(PARAMS)"
	@echo "NC(--no-cache) = $(NC)"
	@echo "PULL(--pull)   = $(PULL)"
	@echo "LOAD_STRATEGY  = $(LOAD_STRATEGY)"

print-image:
	@echo "$(IMAGE)"

# ===== Build =====
build: print-image
	@if [ "$(PORTABLE)" = "1" ]; then \
	  echo "==> Building PORTABLE image (ref=$(REF), subdir=$(SUBDIR), tag=$(IMAGE))"; \
	  docker build $(if $(filter 1,$(PULL)),--pull) $(if $(filter 1,$(NC)),--no-cache) \
	    --build-arg PORTABLE_BUILD=1 \
	    --build-arg EOPF_GEOZARR_REF=$(REF) \
	    --build-arg EOPF_GEOZARR_SUBDIR=$(SUBDIR) \
	    -t $(IMAGE) -f $(DOCKERFILE) . ; \
	else \
	  echo "==> Building WHEEL image for $(PLATFORM) (ref=$(REF), subdir=$(SUBDIR), tag=$(IMAGE))"; \
	  docker buildx build --platform=$(PLATFORM) \
	    $(if $(filter 1,$(PULL)),--pull) $(if $(filter 1,$(NC)),--no-cache) \
	    --build-arg PORTABLE_BUILD=0 \
	    --build-arg EOPF_GEOZARR_REF=$(REF) \
	    --build-arg EOPF_GEOZARR_SUBDIR=$(SUBDIR) \
	    -t $(IMAGE) --load -f $(DOCKERFILE) . ; \
	fi

push:
	docker push $(IMAGE)

.PHONY: load _check-image load-k3d load-minikube

_check-image:
	@docker image inspect $(IMAGE) >/dev/null 2>&1 || \
	  (echo "Image $(IMAGE) not found locally. Run: make build"; exit 2)

load: _check-image
	@set -euo pipefail; \
	case "$(LOAD_STRATEGY)" in \
	  k3d)       $(MAKE) load-k3d ;; \
	  minikube)  $(MAKE) load-minikube ;; \
	  push)      $(MAKE) push ;; \
	  auto|"") \
	    echo "==> Auto-detecting loader"; \
	    if command -v k3d >/dev/null 2>&1 && k3d cluster list | awk 'NR>1{print $$1}' | grep -qx "$(CLUSTER)"; then \
	      $(MAKE) load-k3d; \
	    elif command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then \
	      $(MAKE) load-minikube; \
	    else \
	      echo "No local k3d/minikube cluster detected. Use: make push (or set LOAD_STRATEGY=push)."; \
	      exit 2; \
	    fi ;; \
	  *) \
	    echo "Unknown LOAD_STRATEGY='$(LOAD_STRATEGY)'"; \
	    exit 2 ;; \
	esac

load-k3d: _check-image
	@echo "==> Importing $(IMAGE) into k3d ($(CLUSTER))"
	@k3d image import $(IMAGE) --cluster $(CLUSTER)

load-minikube: _check-image
	@echo "==> Loading $(IMAGE) into minikube"
	minikube image load $(IMAGE)

# ===== Argo & template =====
argo-install:
	kubectl create ns $(NAMESPACE) 2>/dev/null || true
	kubectl apply -n $(NAMESPACE) -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.1/install.yaml
	kubectl -n $(NAMESPACE) rollout status deploy/workflow-controller
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server

template:
	@mkdir -p $(WORKDIR)
	@echo "==> Rendering $(TPL) with image $(IMAGE) and imagePullPolicy=$(PULLPOL)"
	@sed -E \
	  -e 's#^([[:space:]]*image:[[:space:]]*).*#\1$(IMAGE)#' \
	  -e 's#^([[:space:]]*imagePullPolicy:[[:space:]]*).*#\1$(PULLPOL)#' \
	  $(TPL) > $(WORKDIR)/tpl.rendered.yaml
	kubectl -n $(NAMESPACE) apply -f $(WORKDIR)/tpl.rendered.yaml
	kubectl -n $(NAMESPACE) get workflowtemplate geozarr-convert -o yaml | sed -n '1,40p'

# ===== Convenience targets =====
apply: build load argo-install template
	@echo "==> apply done"

dev: build load template
	@echo "==> dev cycle complete"

# ===== Submissions =====
submit: _ensure-dirs
	@STAC=$${STAC_URL:-$$(jq -r '.arguments.parameters[] | select(.name=="stac_url").value' $(PARAMS))}; \
	OUT=$${OUTPUT_ZARR:-$$(jq -r '.arguments.parameters[] | select(.name=="output_zarr").value' $(PARAMS))}; \
	JSON_GRP=$$(jq -r '.arguments.parameters[] | select(.name=="groups").value' $(PARAMS)); \
	GRP="$(if $(strip $(ZARR_GROUPS)),$(value ZARR_GROUPS),$${JSON_GRP})"; \
	echo "Submitting:"; echo "  stac_url=$$STAC"; echo "  output_zarr=$$OUT"; echo "  groups=$$GRP"; \
	WF=$$(argo submit -n $(NAMESPACE) --from workflowtemplate/geozarr-convert \
	  -p stac_url="$$STAC" -p output_zarr="$$OUT" -p groups="$$GRP" -o name); \
	TSTAMP=$$(date +%Y%m%d-%H%M%S); \
	argo get -n $(NAMESPACE) $$WF -o json > runs/$${TSTAMP}-$${WF##*/}.json; \
	argo get -n $(NAMESPACE) $$WF --output wide | tee runs/$${TSTAMP}-$${WF##*/}.summary.txt; \
	echo "Workflow: $$WF"

submit-cli: _ensure-dirs
	@JSON_GRP=$$(jq -r '.arguments.parameters[] | select(.name=="groups").value' $(PARAMS)); \
	GRP="$(if $(strip $(ZARR_GROUPS)),$(value ZARR_GROUPS),$${JSON_GRP})"; \
	WF=$$(argo submit -n $(NAMESPACE) --from workflowtemplate/geozarr-convert \
	  -p stac_url="$$(jq -r '.arguments.parameters[] | select(.name=="stac_url").value' $(PARAMS))" \
	  -p output_zarr="$$(jq -r '.arguments.parameters[] | select(.name=="output_zarr").value' $(PARAMS))" \
	  -p groups="$$GRP" -o name); \
	TSTAMP=$$(date +%Y%m%d-%H%M%S); \
	argo get -n $(NAMESPACE) $$WF -o json > runs/$${TSTAMP}-$${WF##*/}.json; \
	argo get -n $(NAMESPACE) $$WF --output wide | tee runs/$${TSTAMP}-$${WF##*/}.summary.txt; \
	echo "Workflow: $$WF"

submit-api: _ensure-dirs
	kubectl -n $(NAMESPACE) port-forward svc/argo-server 2746:2746 >/dev/null 2>&1 & echo $$! > .pf.pid
	sleep 1
	curl -s -H 'Content-Type: application/json' \
	  --data-binary @$(PARAMS) \
	  http://localhost:2746/api/v1/workflows/$(NAMESPACE)/submit \
	  | tee runs/submit-response.json | jq . >/dev/null || \
	  (echo "Non-JSON response (see runs/submit-response.json)"; exit 1)
	-@[ -f .pf.pid ] && kill $$(cat .pf.pid) 2>/dev/null || true
	-@rm -f .pf.pid

# ===== Inspect & housekeeping =====
status:
	argo list -n $(NAMESPACE); echo; kubectl -n $(NAMESPACE) get wf

latest:
	argo get -n $(NAMESPACE) @latest --output wide

logs-save: _ensure-dirs
	@WF=$$(argo list -n $(NAMESPACE) --output name | tail -1); \
	TSTAMP=$$(date +%Y%m%d-%H%M%S); \
	argo logs -n $(NAMESPACE) $$WF -c main > logs/$${TSTAMP}-$${WF##*/}.log; \
	echo "Wrote logs/$${TSTAMP}-$${WF##*/}.log"

clean:
	argo delete -n $(NAMESPACE) --all || true
	kubectl -n $(NAMESPACE) delete pod -l workflows.argoproj.io/completed=true --force --grace-period=0 || true

_ensure-dirs:
	@mkdir -p runs logs $(WORKDIR)

fetch-tar: _ensure-dirs
	@WF=$$(argo list -n $(NAMESPACE) --output name | tail -1 | sed 's#.*/##'); \
	PVC="$$WF-outpvc"; OUTDIR="runs/$$WF"; \
	echo "Workflow: $$WF"; echo "PVC: $$PVC"; mkdir -p $$OUTDIR; \
	kubectl -n $(NAMESPACE) delete pod fetch-$$WF --ignore-not-found >/dev/null 2>&1 || true; \
	kubectl -n $(NAMESPACE) apply -f - <<-YAML ; \
		apiVersion: v1 \
		kind: Pod \
		metadata: \
		  name: fetch-$$WF \
		spec: \
		  restartPolicy: Never \
		  containers: \
		  - name: fetch \
		    image: busybox:1.36 \
		    command: ["sh","-lc","sleep 600"] \
		    volumeMounts: \
		    - name: out \
		      mountPath: /mnt/out \
		  volumes: \
		  - name: out \
		    persistentVolumeClaim: \
		      claimName: $$PVC \
	YAML
	kubectl -n $(NAMESPACE) wait --for=condition=Ready pod/fetch-$$WF --timeout=60s
	kubectl -n $(NAMESPACE) cp fetch-$$WF:/mnt/out/geozarr.tar.gz $$OUTDIR/geozarr.tar.gz
	tar -xzf $$OUTDIR/geozarr.tar.gz -C $$OUTDIR
	kubectl -n $(NAMESPACE) cp fetch-$$WF:/mnt/out/. $$OUTDIR/ || true
	kubectl -n $(NAMESPACE) delete pod fetch-$$WF --wait=false
	@echo "Unpacked into $$OUTDIR/"

run: apply submit fetch-tar

clean-pvc:
	kubectl -n $(NAMESPACE) delete pvc -l workflows.argoproj.io/workflow 2>/dev/null || true
