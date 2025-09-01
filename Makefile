# Minimal remote-first Makefile for running GeoZarr conversions on Argo Workflows

# Image/tag (Docker Hub)
DOCKERHUB_ORG ?= wietzesuijker
DOCKERHUB_REPO ?= eopf-geozarr
TAG ?= dev

# Build platform for the remote cluster
REMOTE_PLATFORM ?= linux/amd64

# Workflow params
PARAMS_FILE ?= params.json

# Remote Argo (EOXHub)
ARGO_REMOTE_SERVER ?= https://argo-workflows.hub-eopf-explorer.eox.at
REMOTE_NAMESPACE ?= devseed
REMOTE_SERVICE_ACCOUNT ?= devseed
ARGO_AUTH_MODE ?= sso
ARGO_TLS_INSECURE ?= true
ARGO_CA_FILE ?=

# Export to child processes so scripts/argo_remote.sh picks them up
export ARGO_REMOTE_SERVER
export REMOTE_NAMESPACE
export REMOTE_SERVICE_ACCOUNT
export ARGO_AUTH_MODE
export ARGO_TLS_INSECURE
export ARGO_CA_FILE

# Derived
DOCKERHUB_ORG_LC := $(shell printf '%s' '$(DOCKERHUB_ORG)' | tr '[:upper:]' '[:lower:]')
DOCKERHUB_REPO_LC := $(shell printf '%s' '$(DOCKERHUB_REPO)' | tr '[:upper:]' '[:lower:]')
DOCKERHUB_IMAGE := docker.io/$(DOCKERHUB_ORG_LC)/$(DOCKERHUB_REPO_LC):$(TAG)
SUBMIT_IMAGE ?= $(DOCKERHUB_IMAGE)

.PHONY: help publish build tag push template template-delete template-force submit submit-remote logs get ui up doctor env

help:
	@echo "Remote Argo quickstart:"
	@echo "  1) Export your UI token and server:" \
	      "export ARGO_TOKEN='Bearer <paste-from-UI>'" \
	      " ARGO_REMOTE_SERVER=$(ARGO_REMOTE_SERVER)"
	@echo "  2) One-shot run (apply template + submit):   make up"
	@echo "     (or build/publish custom image first:     make publish TAG=$(TAG))"
	@echo "  3) Tail logs:                                make logs"
	@echo "  4) Inspect latest workflow:                  make get"
	@echo "  5) Open namespace UI:                        make ui"
	@echo "Vars you can override: DOCKERHUB_ORG, DOCKERHUB_REPO, TAG, REMOTE_NAMESPACE, SUBMIT_IMAGE"

# ---- Docker Hub publish (remote platform) ----
.PHONY: publish
publish: build tag push
	@echo "Published to $(DOCKERHUB_IMAGE)"

.PHONY: build
build:
	@echo "Building $(DOCKERHUB_IMAGE) for $(REMOTE_PLATFORM) ..."
	docker build --platform $(REMOTE_PLATFORM) -f docker/Dockerfile -t $(DOCKERHUB_IMAGE) .

.PHONY: tag
tag:
	@true # image already built with target tag

.PHONY: push
push:
		@echo "Pushing $(DOCKERHUB_IMAGE) ..."
		docker push $(DOCKERHUB_IMAGE)

# ---- Remote Argo (via scripts/argo_remote.sh) ----

.PHONY: template
template:
	@chmod +x ./scripts/argo_remote.sh || true
		@[ -f workflows/geozarr-convert-template.yaml ] || { echo "workflow template missing"; exit 2; }
		@echo "Applying WorkflowTemplate to $(ARGO_REMOTE_SERVER) in ns=$(REMOTE_NAMESPACE) ..."
		# Try create → update → delete+create (for older CLIs)
		@./scripts/argo_remote.sh template create workflows/geozarr-convert-template.yaml \
		|| ./scripts/argo_remote.sh template update workflows/geozarr-convert-template.yaml \
		|| ( ./scripts/argo_remote.sh template delete geozarr-convert || true; \
				 ./scripts/argo_remote.sh template create workflows/geozarr-convert-template.yaml )

.PHONY: template-delete
template-delete:
	@chmod +x ./scripts/argo_remote.sh || true
	@echo "Deleting WorkflowTemplate geozarr-convert in ns=$(REMOTE_NAMESPACE) ..."
	@./scripts/argo_remote.sh template delete geozarr-convert || true

.PHONY: template-force
template-force: template-delete
	@$(MAKE) template

.PHONY: submit
submit:
	@chmod +x ./scripts/argo_remote.sh ./scripts/argo_submit_workflow.sh || true
	@SUBMIT_IMAGE=$(SUBMIT_IMAGE) PARAMS_FILE=$(PARAMS_FILE) REMOTE_SERVICE_ACCOUNT=$(REMOTE_SERVICE_ACCOUNT) \
		./scripts/argo_submit_workflow.sh

.PHONY: submit-remote
submit-remote: submit

.PHONY: up
up: template submit
	@echo "Tip: use 'make logs' to follow the latest run."

.PHONY: logs
logs:
		@( ./scripts/argo_remote.sh logs @latest -c main -f || ./scripts/argo_remote.sh logs @latest -f ) | sed -u 's/\r//g'

.PHONY: get
get:
		@./scripts/argo_remote.sh get @latest -o wide

.PHONY: ui
ui:
		@NS_TRIM=$$(printf '%s' "$(REMOTE_NAMESPACE)" | tr -d '[:space:]'); \
		BASE=$$(printf '%s' "$(ARGO_REMOTE_SERVER)" | tr -d '[:space:]'); [ -n "$$BASE" ] || BASE="https://argo-workflows.hub-eopf-explorer.eox.at"; \
		URL="$$BASE"; URL="$${URL%/}/workflows/$$NS_TRIM"; \
		echo "Open remote Argo Workflows UI:"; echo "  $$URL"

.PHONY: doctor
doctor:
	@ok=1; \
	if [ -z "$$ARGO_TOKEN" ]; then echo "[doctor] ARGO_TOKEN not set (export a UI token)" >&2; ok=0; fi; \
	if [ -z "$(ARGO_REMOTE_SERVER)" ]; then echo "[doctor] ARGO_REMOTE_SERVER not set" >&2; ok=0; fi; \
	if [ -z "$(REMOTE_NAMESPACE)" ]; then echo "[doctor] REMOTE_NAMESPACE not set" >&2; ok=0; fi; \
	if [ "$$ok" -eq 0 ]; then exit 2; fi; \
	echo "[doctor] Checking remote connectivity ..."; \
	./scripts/argo_remote.sh list >/dev/null 2>&1 || ./scripts/argo_remote.sh get wf >/dev/null 2>&1 || echo "[doctor] argo CLI reachable"; \
	echo "[doctor] OK: environment looks good."

.PHONY: env
env:
	@echo "ARGO_REMOTE_SERVER=$(ARGO_REMOTE_SERVER)"; \
	echo "REMOTE_NAMESPACE=$(REMOTE_NAMESPACE)"; \
	echo "REMOTE_SERVICE_ACCOUNT=$(REMOTE_SERVICE_ACCOUNT)"; \
	echo "SUBMIT_IMAGE=$(SUBMIT_IMAGE)";
