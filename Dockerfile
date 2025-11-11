# Dockerfile for Parrot MCP Server
# Optimized for security and minimal image size

FROM bash:5.2-alpine3.19

# Create non-root user
RUN adduser -D -u 1000 appuser

# Build stage
FROM bash:5.2-alpine3.19 AS builder

WORKDIR /build

# Copy scripts and validate
COPY rpi-scripts/ /build/rpi-scripts/
COPY scripts/ /build/scripts/

# Make scripts executable and validate syntax
RUN find /build -name "*.sh" -type f -exec chmod +x {} \; && \
    find /build -name "*.sh" -type f -exec bash -n {} \;

# Final stage
FROM bash:5.2-alpine3.19

# Create non-root user
RUN adduser -D -u 1000 appuser

WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/logs /app/data && \
    chown -R appuser:appuser /app

# Copy application files from builder
COPY --from=builder --chown=appuser:appuser /build /app/

# Copy additional files
COPY --chown=appuser:appuser README.md /app/

# Switch to non-root user
USER appuser

# Expose port (if needed for future HTTP interface)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD test -f /app/logs/parrot.log || exit 1

# Set environment variables
ENV MCP_SERVER_PORT=8080 \
    MCP_LOG_DIR=/app/logs \
    MCP_DATA_DIR=/app/data

# Default command
CMD ["/bin/bash", "/app/rpi-scripts/start_mcp_server.sh"]
