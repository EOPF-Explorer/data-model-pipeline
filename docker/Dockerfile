# Global base-image args for both stages
ARG BASE_IMAGE=python:3.11-slim
ARG RUNTIME_BASE_IMAGE=python:3.11-slim

# ========= stage: builder =========
FROM ${BASE_IMAGE} AS builder
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
ARG PORTABLE_BUILD=0
ARG EOPF_GEOZARR_REF=main
ARG EOPF_GEOZARR_SUBDIR=
ARG DM_RAW_BASE=https://raw.githubusercontent.com/EOPF-Explorer/data-model

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends       ca-certificates curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Optional toolchain + GDAL/PROJ for sdists (needed in portable mode or fallback)
ENV GDAL_CONFIG=/usr/bin/gdal-config

# Pull lockfiles from data-model@<ref> (optionally a subdir)
RUN set -eux;     mkdir -p /tmp/dm;     curl -fsSL -o /tmp/dm/pyproject.toml "${DM_RAW_BASE}/${EOPF_GEOZARR_REF}/${EOPF_GEOZARR_SUBDIR}pyproject.toml";     curl -fsSL -o /tmp/dm/uv.lock        "${DM_RAW_BASE}/${EOPF_GEOZARR_REF}/${EOPF_GEOZARR_SUBDIR}uv.lock";     test -s /tmp/dm/pyproject.toml && test -s /tmp/dm/uv.lock

# uv + export pinned third-party requirements (exclude eopf-geozarr itself)
RUN pip install -U pip uv && uv --version
RUN set -euo pipefail;     cd /tmp/dm;     uv export --locked --format=requirements-txt --no-hashes -o /tmp/req.raw.txt;     awk 'BEGIN{IGNORECASE=1}       /^-e[[:space:]]/ || /^--editable[[:space:]]/ {next}       /@ file:/ || /file:\/\// {next}       /^eopf-geozarr([[:space:]]|==|$)/ {next}       /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}       {print}' /tmp/req.raw.txt > /tmp/requirements.txt

# Install third-party deps with resilient strategy
RUN set -eux;   if [ "$PORTABLE_BUILD" = "1" ]; then     echo "PORTABLE_BUILD=1: installing build deps + GDAL/PROJ first";     apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends       build-essential pkg-config       gdal-bin libgdal-dev       proj-bin libproj-dev     && rm -rf /var/lib/apt/lists/*;     export GDAL_CONFIG=/usr/bin/gdal-config;     uv pip install --system --requirements /tmp/requirements.txt;   else     echo "Fast path: wheels-only, with automatic fallback to sdists if needed";     if env PIP_ONLY_BINARY=":all:" uv pip install --system --requirements /tmp/requirements.txt; then       echo "Wheels-only install succeeded.";     else       echo "Wheels-only failed; installing build deps + GDAL/PROJ and retrying from sdist...";       apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends         build-essential pkg-config         gdal-bin libgdal-dev         proj-bin libproj-dev       && rm -rf /var/lib/apt/lists/*;       export GDAL_CONFIG=/usr/bin/gdal-config;       uv pip install --system --requirements /tmp/requirements.txt;     fi;   fi

# Install eopf-geozarr itself (follow the data-model repo @ref/subdir)
RUN set -eux;     if [ -n "$EOPF_GEOZARR_SUBDIR" ]; then       PKG_URL="eopf-geozarr @ git+https://github.com/EOPF-Explorer/data-model@${EOPF_GEOZARR_REF}#subdirectory=${EOPF_GEOZARR_SUBDIR%/}";     else       PKG_URL="eopf-geozarr @ git+https://github.com/EOPF-Explorer/data-model@${EOPF_GEOZARR_REF}";     fi;     uv pip install --system --no-deps "$PKG_URL"

RUN python -m compileall -q /usr/local/lib/python3.11/site-packages || true

# ========= stage: runtime =========
FROM ${RUNTIME_BASE_IMAGE} AS runtime
ARG CACHE_BUST=0
LABEL cache.bust="${CACHE_BUST}"
ENV PYTHONUNBUFFERED=1
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends       libstdc++6 libgomp1 libexpat1       gdal-bin proj-bin curl     && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /usr/local /usr/local
COPY scripts/ /app/scripts/
RUN chmod -R a+rX /app && find /app/scripts -type f -name "*.sh" -exec chmod +x {} \; 
ENTRYPOINT ["/bin/bash"]
