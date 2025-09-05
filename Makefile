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
# Optional: set to 'sso' only if you want interactive/browser SSO via argo CLI
ARGO_AUTH_MODE ?=
ARGO_TLS_INSECURE ?= true
ARGO_CA_FILE ?=

# Token settings
TOKEN_DURATION ?= 4320h

# Export to child processes so scripts pick them up
export ARGO_REMOTE_SERVER
export REMOTE_NAMESPACE
export REMOTE_SERVICE_ACCOUNT
export ARGO_AUTH_MODE
export ARGO_TLS_INSECURE
export ARGO_CA_FILE
export TOKEN_DURATION

# Derived
GHCR_ORG_LC := $(shell printf '%s' '$(GHCR_ORG)' | tr '[:upper:]' '[:lower:]')
GHCR_REPO_LC := $(shell printf '%s' '$(GHCR_REPO)' | tr '[:upper:]' '[:lower:]')
GHCR_REGISTRY ?= ghcr.io
GHCR_IMAGE := $(GHCR_REGISTRY)/$(GHCR_ORG_LC)/$(GHCR_REPO_LC):$(TAG)
SUBMIT_IMAGE ?= $(GHCR_IMAGE)

.PHONY: help init publish ensure-token template submit logs get ui up up-force clean doctor env events-apply events-delete token-bootstrap login secret-ovh-s3 secret-ovh-s3-delete

help:
	@echo "Remote Argo quickstart (dense):"
	@echo "  init        → bootstrap exec bits + env check"
	@echo "  up          → build+push, apply template, submit"
	@echo "  up-force    → same as up, but FORCE rebuild (pull+no-cache)"
	@echo "  submit      → resubmit using existing image/params (PARAMS_FILE=params.json)"
	@echo "  logs|ui     → follow latest run or open UI"
	@echo "  clean       → remove local .work proxy/rendered artifacts"
	@echo "  token-bootstrap → mint token via bootstrap workflow (.work/argo.token)"
	@echo "  secret-ovh-s3   → create/update S3 credentials secret (ovh-s3-creds)"
	@echo "Vars: GHCR_ORG, GHCR_REPO, TAG, REMOTE_NAMESPACE, SUBMIT_IMAGE"
	@echo "Docs: See README.md (Overview, Parameters, Troubleshooting, ADR alignment)"
	@true

init:
	@chmod +x ./scripts/*.sh || true
	@$(MAKE) ensure-token || true
	@$(MAKE) doctor

# ---- Docker image (remote platform) ----
publish:
	@echo "Building $(GHCR_IMAGE) for $(REMOTE_PLATFORM) ..."
	docker build $(DOCKER_BUILD_ARGS) --platform $(REMOTE_PLATFORM) -f docker/Dockerfile -t $(GHCR_IMAGE) .
	@echo "Pushing $(GHCR_IMAGE) ..."
	docker push $(GHCR_IMAGE)
	@echo "Published to $(GHCR_IMAGE)"


# ---- Remote Argo helpers ----

# Ensure a token exists before invoking the Argo CLI. If none is found,
# bootstrap a long-lived token and store it at .work/argo.token
ensure-token:
	@if [ -n "$$ARGO_TOKEN" ] || [ -n "$$ARGO_TOKEN_FILE" ] || [ -r ".work/argo.token" ]; then \
		echo "[ensure-token] Using existing token (env or .work/argo.token)"; \
		exit 0; \
	else \
		echo "[ensure-token] No token found. Bootstrapping one now..."; \
		$(MAKE) token-bootstrap; \
	fi

template: ensure-token
	@[ -f workflows/geozarr-convert-template.yaml ] || { echo "workflow template missing"; exit 2; }
	@echo "Applying WorkflowTemplate to $(ARGO_REMOTE_SERVER) in ns=$(REMOTE_NAMESPACE) ..."
	# Try update → create
	@./scripts/argo_remote.sh template update workflows/geozarr-convert-template.yaml \
	|| ./scripts/argo_remote.sh template create workflows/geozarr-convert-template.yaml

# (template-delete and template-force removed; template handles update/replace fallback)

submit: ensure-token
	@SUBMIT_IMAGE=$(SUBMIT_IMAGE) PARAMS_FILE=$(PARAMS_FILE) REMOTE_SERVICE_ACCOUNT=$(REMOTE_SERVICE_ACCOUNT) \
		./scripts/argo_submit_workflow.sh
# (submit-remote alias removed)

up: publish template submit
	@echo "Tip: use 'make logs' to follow the latest run."

up-force:
	@$(MAKE) FORCE=true up

clean:
	@rm -f .work/argo_pf.pid .work/argo_pf.port .work/argo_ui_proxy.port .work/rendered.yaml .work/tpl.rendered.yaml 2>/dev/null || true
	@echo "Cleaned local .work proxy/rendered artifacts (token preserved)"

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
	if [ -z "$$ARGO_TOKEN" ] && [ -z "$$ARGO_TOKEN_FILE" ] && [ ! -r ".work/argo.token" ]; then echo "[doctor] WARN: No token found (set ARGO_TOKEN, ARGO_TOKEN_FILE, or .work/argo.token)" >&2; fi; \
	if [ -z "$(ARGO_REMOTE_SERVER)" ]; then echo "[doctor] ARGO_REMOTE_SERVER not set" >&2; ok=0; fi; \
	if [ -z "$(REMOTE_NAMESPACE)" ]; then echo "[doctor] REMOTE_NAMESPACE not set" >&2; ok=0; fi; \
	if [ "$$ok" -eq 0 ]; then exit 2; fi; \
	echo "[doctor] Checking remote connectivity ..."; \
	./scripts/argo_remote.sh list >/dev/null 2>&1 || ./scripts/argo_remote.sh get wf >/dev/null 2>&1 || true; \
	echo "[doctor] OK: environment looks good."

token-bootstrap:
	@./scripts/bootstrap_argo_token.sh

login:
	@echo "Argo CLI has no 'login' command on this version." ; \
	echo "Use one of the following:" ; \
	echo "  1) Export a token:   export ARGO_TOKEN='Bearer <token>'" ; \
	echo "  2) Put token in file: echo 'Bearer <token>' > .work/argo.token" ; \
	echo "  3) Set ARGO_TOKEN_FILE to your token path" ; \
	echo "Then run: make template / make submit" ; \
	true

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
secret-ovh-s3:
	@[ -n "$$AWS_ACCESS_KEY_ID" ] || { echo "Set AWS_ACCESS_KEY_ID in env"; exit 2; }
	@[ -n "$$AWS_SECRET_ACCESS_KEY" ] || { echo "Set AWS_SECRET_ACCESS_KEY in env"; exit 2; }
	kubectl -n $(REMOTE_NAMESPACE) create secret generic ovh-s3-creds \
		--from-literal=AWS_ACCESS_KEY_ID="$$AWS_ACCESS_KEY_ID" \
		--from-literal=AWS_SECRET_ACCESS_KEY="$$AWS_SECRET_ACCESS_KEY" \
		$(if $(AWS_SESSION_TOKEN),--from-literal=AWS_SESSION_TOKEN="$(AWS_SESSION_TOKEN)",) \
		--dry-run=client -o yaml | kubectl -n $(REMOTE_NAMESPACE) apply -f -
	@echo "Created/updated secret 'ovh-s3-creds' in ns=$(REMOTE_NAMESPACE)"

secret-ovh-s3-delete:
	kubectl -n $(REMOTE_NAMESPACE) delete secret ovh-s3-creds --ignore-not-found
