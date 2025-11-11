# Multi-stage Dockerfile for Parrot MCP Server with Nmap
# Stage 1: Base image with system dependencies
FROM python:3.11-slim as base

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies and Nmap
RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    ncat \
    postgresql-client \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd -m -u 1000 -s /bin/bash parrot && \
    mkdir -p /app /app/logs /app/reports && \
    chown -R parrot:parrot /app

# Stage 2: Dependencies
FROM base as dependencies

WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 3: Application
FROM base as application

WORKDIR /app

# Copy Python dependencies from previous stage
COPY --from=dependencies /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=dependencies /usr/local/bin /usr/local/bin

# Copy application code
COPY --chown=parrot:parrot mcp_server/ ./mcp_server/

# Create necessary directories with proper permissions
RUN mkdir -p /app/logs /app/reports && \
    chown -R parrot:parrot /app && \
    chmod 755 /app/logs /app/reports

# Switch to non-root user
USER parrot

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

# Default command (can be overridden)
CMD ["python", "-m", "gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "mcp_server.app:create_app()"]
