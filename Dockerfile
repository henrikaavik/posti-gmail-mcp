FROM python:3.11-slim

WORKDIR /app

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# uv for dependency mgmt
RUN pip install --no-cache-dir uv

# Pin upstream taylorwilsdon/google_workspace_mcp to current main HEAD
# (commit pinned at deploy time; fall back to main on rebuild)
ARG UPSTREAM_REF=main
RUN git clone --depth 1 --branch ${UPSTREAM_REF} \
    https://github.com/taylorwilsdon/google_workspace_mcp.git /app/upstream

WORKDIR /app/upstream

# Install Python deps
RUN uv sync --frozen --no-dev --extra disk

# Non-root user, owns app dir + creds dir
RUN useradd --create-home --shell /bin/bash app \
    && mkdir -p /app/upstream/store_creds \
    && chown -R app:app /app

# Copy entrypoint as root (so it lands with correct ownership), then drop
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh && chown app:app /entrypoint.sh

USER app

EXPOSE 8000

# Health check hits FastMCP's /health endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
