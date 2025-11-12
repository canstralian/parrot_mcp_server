#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# stop_mcp_server.sh
#
# Description:
#   This script stops the Parrot MCP Server by terminating the process whose PID
#   is stored in the PID file. It logs all actions and errors with structured
#   logging and audit trails.
#
# Usage:
#   ./stop_mcp_server.sh
#
# Behavior:
#   - Checks for the existence of the PID file.
#   - If found, attempts to kill the process and removes the PID file.
#   - Logs success or failure with structured logging and audit trail.
#   - If the PID file is missing, logs a warning and exits with an error.
#
# Exit Codes:
#   0 - Success
#   1 - Failure (e.g., PID file missing or process could not be killed)
# -----------------------------------------------------------------------------

set -euo pipefail

# Get script directory and source common config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

if [ -f "$PARROT_PID_FILE" ]; then
	PID=$(cat "$PARROT_PID_FILE")
	if kill "$PID" 2>/dev/null; then
		rm -f "$PARROT_PID_FILE"
		parrot_info "MCP server stopped (pid $PID)"
		parrot_log_json "INFO" "MCP server stopped" "component=mcp_server" "pid=$PID" "action=stop"
		parrot_audit_log "server_stop" "mcp_server" "success" "pid=$PID"
	else
		parrot_error "Failed to kill MCP server process (pid $PID)"
		parrot_log_json "ERROR" "Failed to stop MCP server" "pid=$PID" "error=kill_failed"
		parrot_audit_log "server_stop" "mcp_server" "error" "pid=$PID" "error=kill_failed"
		exit 1
	fi
else
	parrot_warn "No MCP server PID file found on stop"
	parrot_log_json "WARN" "Stop requested but no PID file found" "status=not_running"
	echo "No MCP server PID file found."
	exit 1
fi
