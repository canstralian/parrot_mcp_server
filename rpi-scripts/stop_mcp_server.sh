#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# stop_mcp_server.sh
#
# Description:
#   This script stops the Parrot MCP Server by terminating the process whose PID
#   is stored in the configured PID file. It logs all actions and errors with
#   a timestamp and unique message ID.
#
# Usage:
#   ./stop_mcp_server.sh
#
# Behavior:
#   - Checks for the existence of the PID file.
#   - If found, attempts to kill the process and removes the PID file.
#   - Logs success or failure to the log file.
#   - If the PID file is missing, logs a warning and exits with an error.
#
# Exit Codes:
#   0 - Success
#   1 - Failure (e.g., PID file missing or process could not be killed)
# -----------------------------------------------------------------------------

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Check if PID file exists
if [ ! -f "$PARROT_PID_FILE" ]; then
	parrot_warn "No MCP server PID file found at: $PARROT_PID_FILE"
	echo "No MCP server PID file found."
	exit 1
fi

# Read PID from file
PID=$(cat "$PARROT_PID_FILE")

# Validate PID is a number
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
	parrot_error "Invalid PID in file: $PID"
	exit 1
fi

# Check if process is actually running
if ! kill -0 "$PID" 2>/dev/null; then
	parrot_warn "Process $PID is not running (stale PID file)"
	rm -f "$PARROT_PID_FILE"
	echo "Process was not running. Cleaned up stale PID file."
	exit 0
fi

# Attempt to stop the process
if kill "$PID" 2>/dev/null; then
	# Wait for process to terminate
	timeout=5
	count=0
	while kill -0 "$PID" 2>/dev/null && [ $count -lt $timeout ]; do
		sleep 1
		count=$((count + 1))
	done

	# Force kill if still running
	if kill -0 "$PID" 2>/dev/null; then
		parrot_warn "Process $PID did not terminate gracefully, forcing..."
		kill -9 "$PID" 2>/dev/null || true
		sleep 1
	fi

	rm -f "$PARROT_PID_FILE"
	parrot_info "MCP server stopped (PID: $PID)"
	echo "MCP server stopped successfully."
else
	parrot_error "Failed to kill MCP server process (PID: $PID)"
	exit 1
fi
