#!/usr/bin/env bash
# =============================================================================
# stop_mcp_server.sh - Stop the Parrot MCP Server
#
# Description:
#   This script stops the Parrot MCP Server by terminating the process whose
#   PID is stored in the configured PID file. It logs all actions and errors
#   with timestamps and unique message IDs.
#
# Usage:
#   ./stop_mcp_server.sh
#
# Behavior:
#   - Checks for the existence of the PID file
#   - If found, attempts to gracefully terminate the process (SIGTERM)
#   - Falls back to SIGKILL if graceful shutdown fails
#   - Removes the PID file after successful termination
#   - Logs success or failure
#   - If the PID file is missing, logs a warning and exits with an error
#
# Security Improvements:
#   - Uses common_config.sh for consistent configuration
#   - Validates PID before attempting kill
#   - Implements graceful shutdown with fallback
#   - Proper error handling and logging
#
# Exit Codes:
#   0 - Success (server stopped)
#   1 - Failure (e.g., PID file missing or process could not be killed)
# =============================================================================

set -euo pipefail

# Source common configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Initialize directories
parrot_init_log_dir || exit 1
parrot_init_ipc_dir || exit 1

# Set current log for this script
PARROT_CURRENT_LOG="$PARROT_SERVER_LOG"

# Check if PID file exists
if [ ! -f "$PARROT_PID_FILE" ]; then
    parrot_warn "No MCP server PID file found on stop"
    echo "No MCP server PID file found. Server may not be running." >&2
    exit 1
fi

# Read and validate PID
PID=$(cat "$PARROT_PID_FILE" 2>/dev/null || echo "")

if [ -z "$PID" ]; then
    parrot_error "PID file is empty or unreadable"
    rm -f "$PARROT_PID_FILE"
    exit 1
fi

# Validate PID is a number
if ! parrot_validate_number "$PID"; then
    parrot_error "Invalid PID in file: $PID"
    rm -f "$PARROT_PID_FILE"
    exit 1
fi

# Check if process is actually running
if ! kill -0 "$PID" 2>/dev/null; then
    parrot_warn "Process $PID is not running (stale PID file)"
    rm -f "$PARROT_PID_FILE"
    echo "Server process $PID is not running. Cleaned up stale PID file."
    exit 0
fi

# Attempt graceful shutdown (SIGTERM)
parrot_info "Attempting graceful shutdown of MCP server (PID: $PID)"
echo "Stopping MCP server (PID: $PID)..."

if kill -TERM "$PID" 2>/dev/null; then
    # Wait for process to terminate (up to 5 seconds)
    timeout=5
    count=0

    while kill -0 "$PID" 2>/dev/null && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
    done

    # Check if process terminated
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$PARROT_PID_FILE"
        parrot_info "MCP server stopped gracefully (PID: $PID)"
        echo "MCP server stopped successfully"
        exit 0
    else
        # Graceful shutdown failed, force kill
        parrot_warn "Graceful shutdown failed, forcing termination (SIGKILL)"
        echo "Graceful shutdown timed out, forcing termination..."

        if kill -KILL "$PID" 2>/dev/null; then
            sleep 1
            if ! kill -0 "$PID" 2>/dev/null; then
                rm -f "$PARROT_PID_FILE"
                parrot_info "MCP server forcefully terminated (PID: $PID)"
                echo "MCP server forcefully stopped"
                exit 0
            fi
        fi
    fi
fi

# If we get here, something went wrong
parrot_error "Failed to stop MCP server process (PID: $PID)"
echo "ERROR: Failed to stop MCP server process (PID: $PID)" >&2
exit 1
