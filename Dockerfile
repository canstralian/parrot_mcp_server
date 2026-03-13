# Parrot MCP Server — Container Image
# Python 3.11+ required per pyproject.toml
FROM python:3.11-slim

# Security: run as non-root user
RUN groupadd -r parrot && useradd -r -g parrot -d /app -s /sbin/nologin parrot

WORKDIR /app

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests first for layer caching
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy source and install the package (include README for hatchling metadata)
COPY pyproject.toml README.md ./
COPY src/ ./src/
RUN pip install --no-cache-dir -e .

# Runtime directories
RUN mkdir -p /tmp/parrot logs \
    && chown -R parrot:parrot /app /tmp/parrot

# IPC security: override in production with PARROT_IPC_DIR=/run/parrot (700 perms)
ENV PARROT_IPC_DIR=/tmp/parrot \
    ENV=development \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER parrot

EXPOSE 8000

ENTRYPOINT ["./rpi-scripts/start_mcp_server.sh"]
