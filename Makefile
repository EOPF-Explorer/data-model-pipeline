# Minimal remote-first Makefile for running GeoZarr conversions on a remote Argo Workflows cluster

# Image/tag (GHCR)
GHCR_ORG ?= EOPF-Explorer
GHCR_REPO ?= eopf-geozarr
TAG ?= dev

# Build platform for the remote cluster
REMOTE_PLATFORM ?= linux/amd64
# Build behavior (set FORCE=true to pull+no-cache)
FORCE ?=
DOCKER_BUILD_ARGS := $(if $(filter true,$(FORCE)),--pull --no-cache,)

# Workflow params
PARAMS_FILE ?= params.json

# Remote Argo (EOXHub)
ARGO_REMOTE_SERVER ?= https://argo-workflows.hub-eopf-explorer.eox.at
REMOTE_NAMESPACE ?= devseed
REMOTE_SERVICE_ACCOUNT ?= devseed
ARGO_AUTH_MODE ?= sso
ARGO_TLS_INSECURE ?= true
ARGO_CA_FILE ?=

# Export to child processes so scripts pick them up
export ARGO_REMOTE_SERVER
export REMOTE_NAMESPACE
export REMOTE_SERVICE_ACCOUNT
export ARGO_AUTH_MODE
export ARGO_TLS_INSECURE
export ARGO_CA_FILE

# Derived
GHCR_ORG_LC := $(shell printf '%s' '$(GHCR_ORG)' | tr '[:upper:]' '[:lower:]')
GHCR_REPO_LC := $(shell printf '%s' '$(GHCR_REPO)' | tr '[:upper:]' '[:lower:]')
GHCR_REGISTRY ?= ghcr.io
GHCR_IMAGE := $(GHCR_REGISTRY)/$(GHCR_ORG_LC)/$(GHCR_REPO_LC):$(TAG)
SUBMIT_IMAGE ?= $(GHCR_IMAGE)

.PHONY: help init publish template submit logs get ui up doctor env events-apply events-delete

help:
	@echo "Remote Argo quickstart:"
	@echo "  1) One-time init (exec bits, env check):     make init"
	@echo "  2) Build+push image and run:                 make up [TAG=$(TAG)] [FORCE=true]"
	@echo "  3) Re-apply template (if changed):           make template"
	@echo "  4) Submit again (same image/params):         make submit [PARAMS_FILE=params.json]"
	@echo "  5) Tail logs / open UI:                      make logs | make ui"
	@echo "Vars: GHCR_ORG, GHCR_REPO, TAG, REMOTE_NAMESPACE, SUBMIT_IMAGE"
	@echo "Secrets: S3 creds (do not commit):             make secret-ovh-s3 AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."

init:
	@chmod +x ./scripts/*.sh || true
	@$(MAKE) doctor

# ---- Docker image (remote platform) ----
publish:
	@echo "Building $(GHCR_IMAGE) for $(REMOTE_PLATFORM) ..."
	docker build $(DOCKER_BUILD_ARGS) --platform $(REMOTE_PLATFORM) -f docker/Dockerfile -t $(GHCR_IMAGE) .
	@echo "Pushing $(GHCR_IMAGE) ..."
	docker push $(GHCR_IMAGE)
	@echo "Published to $(GHCR_IMAGE)"

# ---- Remote Argo helpers ----

template:
	@[ -f workflows/geozarr-convert-template.yaml ] || { echo "workflow template missing"; exit 2; }
	@echo "Applying WorkflowTemplate to $(ARGO_REMOTE_SERVER) in ns=$(REMOTE_NAMESPACE) ..."
	# Try update → create
	@./scripts/argo_remote.sh template update workflows/geozarr-convert-template.yaml \
	|| ./scripts/argo_remote.sh template create workflows/geozarr-convert-template.yaml

# (template-delete and template-force removed; template handles update/replace fallback)

submit:
	@SUBMIT_IMAGE=$(SUBMIT_IMAGE) PARAMS_FILE=$(PARAMS_FILE) REMOTE_SERVICE_ACCOUNT=$(REMOTE_SERVICE_ACCOUNT) \
		./scripts/argo_submit_workflow.sh
# (submit-remote alias removed)

up: publish template submit
	@echo "Tip: use 'make logs' to follow the latest run."

logs:
		@( ./scripts/argo_remote.sh logs @latest -c main -f || ./scripts/argo_remote.sh logs @latest -f ) | sed -u 's/\r//g'

get:
		@./scripts/argo_remote.sh get @latest -o wide

ui:
		@NS_TRIM=$$(printf '%s' "$(REMOTE_NAMESPACE)" | tr -d '[:space:]'); \
		BASE=$$(printf '%s' "$(ARGO_REMOTE_SERVER)" | tr -d '[:space:]'); [ -n "$$BASE" ] || BASE="https://argo-workflows.hub-eopf-explorer.eox.at"; \
		URL="$$BASE"; URL="$${URL%/}/workflows/$$NS_TRIM"; \
		echo "Open remote Argo Workflows UI:"; echo "  $$URL"

doctor:
	@ok=1; \
	if [ -z "$$ARGO_TOKEN" ]; then echo "[doctor] ARGO_TOKEN not set (export a UI token)" >&2; ok=0; fi; \
	if [ -z "$(ARGO_REMOTE_SERVER)" ]; then echo "[doctor] ARGO_REMOTE_SERVER not set" >&2; ok=0; fi; \
	if [ -z "$(REMOTE_NAMESPACE)" ]; then echo "[doctor] REMOTE_NAMESPACE not set" >&2; ok=0; fi; \
	if [ "$$ok" -eq 0 ]; then exit 2; fi; \
	echo "[doctor] Checking remote connectivity ..."; \
	./scripts/argo_remote.sh list >/dev/null 2>&1 || ./scripts/argo_remote.sh get wf >/dev/null 2>&1 || true; \
	echo "[doctor] OK: environment looks good."

env:
	@echo "ARGO_REMOTE_SERVER=$(ARGO_REMOTE_SERVER)"; \
	echo "REMOTE_NAMESPACE=$(REMOTE_NAMESPACE)"; \
	echo "REMOTE_SERVICE_ACCOUNT=$(REMOTE_SERVICE_ACCOUNT)"; \
	echo "SUBMIT_IMAGE=$(SUBMIT_IMAGE)";

events-apply:
	@[ -f events/amqp-events.yaml ] || { echo "events/amqp-events.yaml missing"; exit 2; }
	@echo "Applying Argo Events EventSource/Sensor in ns=$(REMOTE_NAMESPACE) ..."
	kubectl -n $(REMOTE_NAMESPACE) apply -f events/amqp-events.yaml

events-delete:
	@kubectl -n $(REMOTE_NAMESPACE) delete sensor geozarr-stac-sensor --ignore-not-found
	@kubectl -n $(REMOTE_NAMESPACE) delete eventsource geozarr-amqp --ignore-not-found

# ---- Secrets helpers (never commit credentials) ----
.PHONY: secret-ovh-s3 secret-ovh-s3-delete
secret-ovh-s3:
	@[ -n "$$AWS_ACCESS_KEY_ID" ] || { echo "Set AWS_ACCESS_KEY_ID in env"; exit 2; }
	@[ -n "$$AWS_SECRET_ACCESS_KEY" ] || { echo "Set AWS_SECRET_ACCESS_KEY in env"; exit 2; }
	kubectl -n $(REMOTE_NAMESPACE) create secret generic ovh-s3-creds \
		--from-literal=AWS_ACCESS_KEY_ID="$$AWS_ACCESS_KEY_ID" \
		--from-literal=AWS_SECRET_ACCESS_KEY="$$AWS_SECRET_ACCESS_KEY" \
		--dry-run=client -o yaml | kubectl -n $(REMOTE_NAMESPACE) apply -f -
	@echo "Created/updated secret 'ovh-s3-creds' in ns=$(REMOTE_NAMESPACE)"

secret-ovh-s3-delete:
	kubectl -n $(REMOTE_NAMESPACE) delete secret ovh-s3-creds --ignore-not-found
