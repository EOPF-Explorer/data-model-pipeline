# Global base-image args for both stages
ARG BASE_IMAGE=python:3.11-slim
ARG RUNTIME_BASE_IMAGE=python:3.11-slim

# ========= stage: builder =========
FROM ${BASE_IMAGE} AS builder
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    GDAL_CONFIG=/usr/bin/gdal-config

# Build-time knobs
ARG PORTABLE_BUILD=0
# Git ref of the eopf-geozarr source (branch, tag, or commit)
ARG EOPF_GEOZARR_REF=main
# Repo URL for the data-model project containing eopf-geozarr
ARG EOPF_GEOZARR_REPO_URL=https://github.com/EOPF-Explorer/data-model.git

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Optional toolchain + GDAL/PROJ for source builds (portable mode)
RUN set -eux; \
    if [ "$PORTABLE_BUILD" = "1" ]; then \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    gdal-bin libgdal-dev \
    proj-bin libproj-dev; \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Install uv and the GeoZarr converter from GitHub (not on PyPI)
RUN set -eux; \
    pip install -U pip uv; \
    echo "Cloning ${EOPF_GEOZARR_REPO_URL} @ ${EOPF_GEOZARR_REF} ..."; \
    git clone --depth 1 --branch "${EOPF_GEOZARR_REF}" "${EOPF_GEOZARR_REPO_URL}" /tmp/data-model; \
    cd /tmp/data-model; \
    if uv pip install --system .; then \
    echo "Installed eopf-geozarr successfully (no native build needed)."; \
    else \
    echo "Initial install failed, installing build toolchain + GDAL/PROJ and retrying..."; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    gdal-bin libgdal-dev \
    proj-bin libproj-dev; \
    rm -rf /var/lib/apt/lists/*; \
    uv pip install --system .; \
    fi; \
    cd /; rm -rf /tmp/data-model

# Precompile stdlib/site-packages (best-effort)
RUN python -m compileall -q /usr/local/lib/python3.11/site-packages || true

# ========= stage: runtime =========
FROM ${RUNTIME_BASE_IMAGE} AS runtime
ARG CACHE_BUST=0
LABEL cache.bust="${CACHE_BUST}"
ENV PYTHONUNBUFFERED=1

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash \
    libstdc++6 \
    libgomp1 \
    libexpat1 \
    gdal-bin \
    proj-bin \
    curl; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local /usr/local
COPY scripts/ /app/scripts/
RUN chmod -R a+rX /app && find /app/scripts -type f -name "*.sh" -exec chmod +x {} \;

# AWS CLI for S3-compatible uploads (e.g., OVHcloud Object Storage)
RUN pip install --no-cache-dir -U awscli

ENTRYPOINT ["/bin/bash"]
