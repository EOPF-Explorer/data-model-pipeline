# ===== User-configurable defaults =====
IMAGE_REG ?= ghcr.io/eopf-explorer/data-model-pipeline
TAG       ?= dev
REF       ?= main                 # data-model git ref for eopf-geozarr
PORTABLE  ?=                      # set to 1 to enable system GDAL/PROJ toolchain
NAMESPACE ?= argo
CLUSTER   ?= k3s-default

# Prefer linux/amd64 unless you're on arm64
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
  PLATFORM ?= linux/arm64
else ifeq ($(HOST_ARCH),aarch64)
  PLATFORM ?= linux/arm64
else
  PLATFORM ?= linux/amd64
endif

# Auto-detect Dockerfile path: docker/Dockerfile or fallback to ./Dockerfile
DOCKERFILE ?= $(shell [ -f docker/Dockerfile ] && echo docker/Dockerfile || echo Dockerfile)

# Common paths
IMAGE     := $(IMAGE_REG):$(TAG)
TPL       ?= workflows/geozarr-convert-template.yaml
PARAMS    ?= params.json

# Runtime param overrides (env > PARAMS file)
STAC_URL    ?=
OUTPUT_ZARR ?=
GROUPS      ?=

.PHONY: help build push load-k3d load-minikube argo-install template apply \
        submit submit-cli submit-api status latest logs-save clean \
        _ensure-dirs fetch-tar run clean-pvc print-config

help:
	@echo "Targets:"
	@echo "  build            Build image (PORTABLE=1 for system GDAL/PROJ)."
	@echo "  push             Push image to registry."
	@echo "  load-k3d         Import image into k3d cluster ($(CLUSTER))."
	@echo "  argo-install     Install Argo Workflows in namespace $(NAMESPACE)."
	@echo "  template         Apply/update WorkflowTemplate."
	@echo "  apply            build + load-k3d + argo-install + template."
	@echo "  submit           Submit workflow (env overrides > $(PARAMS))."
	@echo "  fetch-tar        Fetch artifacts from PVC (latest run)."
	@echo "  clean            Delete all workflows + completed pods."
	@echo "  clean-pvc        Delete per-run PVCs."
	@echo "  print-config     Show effective build config."

print-config:
	@echo "IMAGE      = $(IMAGE)"
	@echo "REF        = $(REF)"
	@echo "PORTABLE   = $(PORTABLE)"
	@echo "PLATFORM   = $(PLATFORM)"
	@echo "DOCKERFILE = $(DOCKERFILE)"
	@echo "NAMESPACE  = $(NAMESPACE)"
	@echo "CLUSTER    = $(CLUSTER)"
	@echo "TPL        = $(TPL)"
	@echo "PARAMS     = $(PARAMS)"

# Build the image locally
# make build                 -> WHEEL mode (small), builds for $(PLATFORM)
# make build PORTABLE=1      -> PORTABLE mode (bigger), builds for native arch with GDAL/PROJ toolchain
build:
	@if [ "$(PORTABLE)" = "1" ]; then \
	  echo "==> Building PORTABLE image (ref=$(REF), subdir=$(SUBDIR))"; \
	  docker build \
	    --build-arg PORTABLE_BUILD=1 \
	    --build-arg EOPF_GEOZARR_REF=$(REF) \
	    --build-arg EOPF_GEOZARR_SUBDIR=$(SUBDIR) \
	    -t $(IMAGE) -f docker/Dockerfile . ; \
	else \
	  echo "==> Building WHEEL image for linux/amd64 (ref=$(REF), subdir=$(SUBDIR))"; \
	  docker buildx build --platform=linux/amd64 \
	    --build-arg PORTABLE_BUILD=0 \
	    --build-arg EOPF_GEOZARR_REF=$(REF) \
	    --build-arg EOPF_GEOZARR_SUBDIR=$(SUBDIR) \
	    -t $(IMAGE) --load -f docker/Dockerfile . ; \
	fi

# Push image to registry
push:
	docker push $(IMAGE)

# Load image into k3d’s containerd (dev clusters)
load-k3d:
	k3d image import $(IMAGE) --cluster $(CLUSTER) || \
	  (docker save $(IMAGE) | docker exec -i $$(docker ps --format '{{.Names}}' | grep $(CLUSTER)-server-0) ctr -n k8s.io images import -)

# Build inside minikube’s Docker (respects PORTABLE/REF)
load-minikube:
	@if [ "$(PORTABLE)" = "1" ]; then \
	  eval "$$(minikube docker-env)"; \
	  docker build \
	    --build-arg PORTABLE_BUILD=1 \
	    --build-arg EOPF_GEOZARR_REF=$(REF) \
	    -t $(IMAGE) -f $(DOCKERFILE) . ; \
	else \
	  eval "$$(minikube docker-env)"; \
	  docker build \
	    --build-arg PORTABLE_BUILD=0 \
	    --build-arg EOPF_GEOZARR_REF=$(REF) \
	    -t $(IMAGE) -f $(DOCKERFILE) . ; \
	fi

# Install Argo Workflows (v3.7.1) into $(NAMESPACE)
argo-install:
	kubectl create ns $(NAMESPACE) 2>/dev/null || true
	kubectl apply -n $(NAMESPACE) -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.1/install.yaml
	kubectl -n $(NAMESPACE) rollout status deploy/workflow-controller
	kubectl -n $(NAMESPACE) rollout status deploy/argo-server

# Apply (or update) the WorkflowTemplate
template:
	kubectl -n $(NAMESPACE) apply -f $(TPL)
	kubectl -n $(NAMESPACE) get workflowtemplate geozarr-convert

# One-shot: build + load + install + template
apply: build load-k3d argo-install template

# Submit via CLI (uses env overrides, else PARAMS file)
submit: _ensure-dirs
	@STAC="$${STAC_URL:-$$(jq -r '.arguments.parameters[] | select(.name=="stac_url").value' $(PARAMS))}"; \
	OUT="$${OUTPUT_ZARR:-$$(jq -r '.arguments.parameters[] | select(.name=="output_zarr").value' $(PARAMS))}"; \
	GRP="$${GROUPS:-$$(jq -r '.arguments.parameters[] | select(.name=="groups").value' $(PARAMS))}"; \
	echo "Submitting:"; echo "  stac_url=$$STAC"; echo "  output_zarr=$$OUT"; echo "  groups=$$GRP"; \
	WF=$$(argo submit -n $(NAMESPACE) --from workflowtemplate/geozarr-convert \
	  -p stac_url="$$STAC" -p output_zarr="$$OUT" -p groups="$$GRP" -o name); \
	TSTAMP=$$(date +%Y%m%d-%H%M%S); \
	argo get -n $(NAMESPACE) $$WF -o json > runs/$${TSTAMP}-$${WF##*/}.json; \
	argo get -n $(NAMESPACE) $$WF --output wide | tee runs/$${TSTAMP}-$${WF##*/}.summary.txt; \
	echo "Workflow: $$WF"

# Submit via CLI (PARAMS file only, no env overrides)
submit-cli: _ensure-dirs
	@WF=$$(argo submit -n $(NAMESPACE) --from workflowtemplate/geozarr-convert \
	  -p stac_url="$$(jq -r '.arguments.parameters[] | select(.name=="stac_url").value' $(PARAMS))" \
	  -p output_zarr="$$(jq -r '.arguments.parameters[] | select(.name=="output_zarr").value' $(PARAMS))" \
	  -p groups="$$(jq -r '.arguments.parameters[] | select(.name=="groups").value' $(PARAMS))" \
	  -o name); \
	TSTAMP=$$(date +%Y%m%d-%H%M%S); \
	argo get -n $(NAMESPACE) $$WF -o json > runs/$${TSTAMP}-$${WF##*/}.json; \
	argo get -n $(NAMESPACE) $$WF --output wide | tee runs/$${TSTAMP}-$${WF##*/}.summary.txt; \
	echo "Workflow: $$WF"

# Submit via Argo Server HTTP (dev port-forward, no token)
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

# Inspect
status:
	argo list -n $(NAMESPACE); echo; kubectl -n $(NAMESPACE) get wf

latest:
	argo get -n $(NAMESPACE) @latest --output wide

logs-save: _ensure-dirs
	@WF=$$(argo list -n $(NAMESPACE) --output name | tail -1); \
	TSTAMP=$$(date +%Y%m%d-%H%M%S); \
	argo logs -n $(NAMESPACE) $$WF -c main > logs/$${TSTAMP}-$${WF##*/}.log; \
	echo "Wrote logs/$${TSTAMP}-$${WF##*/}.log"

# Delete all workflows + completed pods
clean:
	argo delete -n $(NAMESPACE) --all || true
	kubectl -n $(NAMESPACE) delete pod -l workflows.argoproj.io/completed=true --force --grace-period=0 || true

_ensure-dirs:
	@mkdir -p runs logs

# Fetch from PVC: copy tarball, unpack into runs/<WF>/, pull any extra files on /outputs
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

# Convenience: build + load + template + submit + fetch
run: apply submit fetch-tar

# Cleanup stray per-run PVCs (removes stored artifacts)
clean-pvc:
	kubectl -n $(NAMESPACE) delete pvc -l workflows.argoproj.io/workflow 2>/dev/null || true
