# ========= stage: builder =========
FROM python:3.11-slim AS builder
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
ARG PORTABLE_BUILD=0
ARG EOPF_GEOZARR_REF=main
ARG EOPF_GEOZARR_SUBDIR=
ARG DM_RAW_BASE=https://raw.githubusercontent.com/EOPF-Explorer/data-model

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Toolchain + GDAL/PROJ for sdist builds (enabled when PORTABLE_BUILD=1)
RUN if [ "$PORTABLE_BUILD" = "1" ]; then \
      apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential pkg-config \
        gdal-bin libgdal-dev \
        proj-bin libproj-dev \
      && rm -rf /var/lib/apt/lists/* ; \
    fi
ENV GDAL_CONFIG=/usr/bin/gdal-config

# Pull lockfiles from data-model@<ref> (optionally a subdir)
RUN set -eux; \
    mkdir -p /tmp/dm; \
    curl -fsSL -o /tmp/dm/pyproject.toml "${DM_RAW_BASE}/${EOPF_GEOZARR_REF}/${EOPF_GEOZARR_SUBDIR}pyproject.toml"; \
    curl -fsSL -o /tmp/dm/uv.lock        "${DM_RAW_BASE}/${EOPF_GEOZARR_REF}/${EOPF_GEOZARR_SUBDIR}uv.lock"; \
    test -s /tmp/dm/pyproject.toml && test -s /tmp/dm/uv.lock

# uv + export pinned requirements (filter out self)
RUN pip install -U pip uv && uv --version
RUN set -euo pipefail; \
    cd /tmp/dm; \
    uv export --locked --format=requirements-txt --no-hashes -o /tmp/req.raw.txt; \
    awk 'BEGIN{IGNORECASE=1} \
      /^-e[[:space:]]/ || /^--editable[[:space:]]/ {next} \
      /@ file:/ || /file:\/\// {next} \
      /^eopf-geozarr([[:space:]]|==|$)/ {next} \
      /^[[:space:]]*#/ || /^[[:space:]]*$/ {next} \
      {print}' /tmp/req.raw.txt > /tmp/requirements.txt

# Install third-party deps
# - portable (PORTABLE_BUILD=1): allow sdists (toolchain present)
# - wheel mode (PORTABLE_BUILD=0): force wheels only → fail fast if missing
RUN if [ "$PORTABLE_BUILD" = "1" ]; then \
      uv pip install --system --requirements /tmp/requirements.txt ; \
    else \
      env PIP_ONLY_BINARY=":all:" uv pip install --system --requirements /tmp/requirements.txt ; \
    fi

# Install eopf-geozarr itself (no deps; already synced)
RUN set -eux; \
    if [ -n "$EOPF_GEOZARR_SUBDIR" ]; then \
      PKG_URL="eopf-geozarr @ git+https://github.com/EOPF-Explorer/data-model@${EOPF_GEOZARR_REF}#subdirectory=${EOPF_GEOZARR_SUBDIR%/}"; \
    else \
      PKG_URL="eopf-geozarr @ git+https://github.com/EOPF-Explorer/data-model@${EOPF_GEOZARR_REF}"; \
    fi; \
    uv pip install --system --no-deps "$PKG_URL"

RUN python -m compileall -q /usr/local/lib/python3.11/site-packages || true

# ========= stage: runtime =========
FROM python:3.11-slim AS runtime
ENV PYTHONUNBUFFERED=1
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libstdc++6 libgomp1 libexpat1 \
      gdal-bin proj-bin curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /usr/local /usr/local
CMD ["python","-V"]
