# Minimal remote-first Makefile for running GeoZarr conversions on a remote Argo Workflows cluster

# Image/tag (Docker Hub)
DOCKERHUB_ORG ?= wietzesuijker
DOCKERHUB_REPO ?= eopf-geozarr
TAG ?= dev

# Build platform for the remote cluster
REMOTE_PLATFORM ?= linux/amd64
# Build behavior
NO_CACHE ?=
PULL ?=
# Derived docker build flags from toggles (set NO_CACHE=true and/or PULL=true)
DOCKER_BUILD_ARGS := $(if $(filter true,$(PULL)),--pull,) $(if $(filter true,$(NO_CACHE)),--no-cache,)

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
DOCKERHUB_ORG_LC := $(shell printf '%s' '$(DOCKERHUB_ORG)' | tr '[:upper:]' '[:lower:]')
DOCKERHUB_REPO_LC := $(shell printf '%s' '$(DOCKERHUB_REPO)' | tr '[:upper:]' '[:lower:]')
DOCKERHUB_IMAGE := docker.io/$(DOCKERHUB_ORG_LC)/$(DOCKERHUB_REPO_LC):$(TAG)
SUBMIT_IMAGE ?= $(DOCKERHUB_IMAGE)

.PHONY: help publish publish-force template submit logs get ui up up-force doctor env events-apply events-delete

help:
	@echo "Remote Argo quickstart:"
	@echo "  1) Export your UI token and server:" \
	      "export ARGO_TOKEN='Bearer <paste-from-UI>'" \
	      " ARGO_REMOTE_SERVER=$(ARGO_REMOTE_SERVER)"
	@echo "  2) One-shot run (check + build+push + apply + submit):"
	@echo "     make up TAG=$(TAG)"
	@echo "     Fast re-run (submit only, same image):"
	@echo "     make submit"
	@echo "  3) Tail logs:                                make logs"
	@echo "  4) Inspect latest workflow:                  make get"
	@echo "  5) Open namespace UI:                        make ui"
	@echo "  Tip: force rebuild to bypass cache:          make up-force  (or: make publish-force)"
	@echo "  6) (Optional) Wire AMQP → Argo Events:       make events-apply"
	@echo "Vars you can override: DOCKERHUB_ORG, DOCKERHUB_REPO, TAG, REMOTE_NAMESPACE, SUBMIT_IMAGE"
	@echo "Secrets: create OVH S3 creds (do not commit): make secret-ovh-s3 AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."

# ---- Docker image (remote platform) ----
publish:
	@echo "Building $(DOCKERHUB_IMAGE) for $(REMOTE_PLATFORM) ..."
	docker build $(DOCKER_BUILD_ARGS) --platform $(REMOTE_PLATFORM) -f docker/Dockerfile -t $(DOCKERHUB_IMAGE) .
	@echo "Pushing $(DOCKERHUB_IMAGE) ..."
	docker push $(DOCKERHUB_IMAGE)
	@echo "Published to $(DOCKERHUB_IMAGE)"

publish-force:
	@echo "Building (force) $(DOCKERHUB_IMAGE) for $(REMOTE_PLATFORM) ..."
	docker build --pull --no-cache --platform $(REMOTE_PLATFORM) -f docker/Dockerfile -t $(DOCKERHUB_IMAGE) .
	@echo "Pushing $(DOCKERHUB_IMAGE) ..."
	docker push $(DOCKERHUB_IMAGE)
	@echo "Published (force) to $(DOCKERHUB_IMAGE)"

# ---- Remote Argo helpers ----

template:
	@chmod +x ./scripts/argo_remote.sh || true
		@[ -f workflows/geozarr-convert-template.yaml ] || { echo "workflow template missing"; exit 2; }
		@echo "Applying WorkflowTemplate to $(ARGO_REMOTE_SERVER) in ns=$(REMOTE_NAMESPACE) ..."
		# Try create → update → delete+create (for older CLIs)
		@./scripts/argo_remote.sh template create workflows/geozarr-convert-template.yaml \
		|| ./scripts/argo_remote.sh template update workflows/geozarr-convert-template.yaml \
		|| ( ./scripts/argo_remote.sh template delete geozarr-convert || true; \
				 ./scripts/argo_remote.sh template create workflows/geozarr-convert-template.yaml )

# (template-delete and template-force removed; template handles update/replace fallback)

submit:
	@chmod +x ./scripts/argo_remote.sh ./scripts/argo_submit_workflow.sh || true
	@SUBMIT_IMAGE=$(SUBMIT_IMAGE) PARAMS_FILE=$(PARAMS_FILE) REMOTE_SERVICE_ACCOUNT=$(REMOTE_SERVICE_ACCOUNT) \
		./scripts/argo_submit_workflow.sh
# (submit-remote alias removed)

up: doctor publish template submit
	@echo "Tip: use 'make logs' to follow the latest run."

up-force: doctor publish-force template submit
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
