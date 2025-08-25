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

# Optional toolchain & GDAL/PROJ for sdist builds (arm64 / wheel gaps)
RUN if [ "$PORTABLE_BUILD" = "1" ]; then \
      apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gdal-bin libgdal-dev proj-bin libproj-dev && rm -rf /var/lib/apt/lists/* ; \
    fi

# Fetch pyproject.toml and uv.lock from data-model@<ref> (optionally a subdir)
RUN set -eux; \
    SUBDIR="${EOPF_GEOZARR_SUBDIR}"; \
    mkdir -p /tmp/dm; \
    curl -fsSL -o /tmp/dm/pyproject.toml "${DM_RAW_BASE}/${EOPF_GEOZARR_REF}/${SUBDIR}pyproject.toml"; \
    curl -fsSL -o /tmp/dm/uv.lock        "${DM_RAW_BASE}/${EOPF_GEOZARR_REF}/${SUBDIR}uv.lock"; \
    test -s /tmp/dm/pyproject.toml && test -s /tmp/dm/uv.lock

# Export pinned third-party deps with uv (run from the project dir)
RUN pip install -U pip uv && uv --version
RUN set -euo pipefail; \
    cd /tmp/dm; \
    uv export --locked --format=requirements-txt --no-hashes -o /tmp/req.raw.txt; \
    awk 'BEGIN{IGNORECASE=1} \
      /^-e[[:space:]]/ || /^--editable[[:space:]]/ {next} \
      /@ file:/ || /file:\/\// {next} \
      /^eopf-geozarr([[:space:]]|==|$)/ {next} \
      /^[[:space:]]*#/ || /^[[:space:]]*$/ {next} \
      {print}' /tmp/req.raw.txt > /tmp/requirements.txt; \
    sed -n "1,80p" /tmp/requirements.txt

# Install third-party deps from the exported list
RUN if [ "$PORTABLE_BUILD" = "1" ]; then \
      pip install --no-cache-dir -r /tmp/requirements.txt ; \
    else \
      PIP_ONLY_BINARY=":all:" pip install --no-cache-dir --prefer-binary -r /tmp/requirements.txt ; \
    fi

# Install eopf-geozarr itself WITHOUT deps (already satisfied above)
RUN set -eux; \
    if [ -n "$EOPF_GEOZARR_SUBDIR" ]; then \
      PKG_URL="eopf-geozarr @ git+https://github.com/EOPF-Explorer/data-model@${EOPF_GEOZARR_REF}#subdirectory=${EOPF_GEOZARR_SUBDIR%/}"; \
    else \
      PKG_URL="eopf-geozarr @ git+https://github.com/EOPF-Explorer/data-model@${EOPF_GEOZARR_REF}"; \
    fi; \
    pip install --no-cache-dir --no-deps "$PKG_URL"

# Optional: tiny startup improvement
RUN python -m compileall -q /usr/local/lib/python3.11/site-packages || true

# ========= stage: runtime =========
FROM python:3.11-slim AS runtime
ENV PYTHONUNBUFFERED=1
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libstdc++6 libgomp1 && rm -rf /var/lib/apt/lists/*

# If you rely on system GDAL tools at runtime for PORTABLE builds, you can add:
# RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
#     gdal-bin proj-bin && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local /usr/local
CMD ["python","-V"]
