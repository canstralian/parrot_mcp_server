#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling

set -euo pipefail

# Get script directory and source common config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Start server in background; let parrot_log/parrot_log_json write directly to their
# configured files rather than capturing via shell redirection (which would duplicate
# ERROR-level lines and capture stray numeric output from parrot_metrics_end).
{
	# Track startup time for metrics
	START_TIME=$(parrot_metrics_start)

	parrot_info "MCP server starting"
	parrot_log_json "INFO" "MCP server started" "component=mcp_server" "action=startup"
	parrot_audit_log "server_start" "mcp_server" "success"

	# Simulate handling a valid MCP message — use configured IPC paths
	if [ -f "$PARROT_MCP_INPUT" ]; then
		if grep -q '"content":"ping"' "$PARROT_MCP_INPUT"; then
			MSG_START=$(parrot_metrics_start)
			parrot_info "MCP message received: ping"
			parrot_log_json "INFO" "MCP message processed" "message_type=ping" "status=success"
			# Capture duration to avoid numeric output polluting any parent stdout
			_msg_duration=$(parrot_metrics_end "$MSG_START" "mcp_message_process" "success" "message_type=ping" 2>&1) || true
		else
			parrot_warn "MCP message file present but no ping content"
			parrot_log_json "WARN" "Invalid MCP message content" "status=invalid"
		fi
	else
		parrot_warn "No valid MCP message file found"
	fi

	# Simulate handling a malformed MCP message — use configured IPC path
	if [ -f "$PARROT_MCP_BAD" ]; then
		parrot_error "Malformed MCP message received"
		parrot_log_json "ERROR" "Malformed MCP message" "status=error" "error_type=malformed_json"
		parrot_audit_log "message_error" "$PARROT_MCP_BAD" "error" "error_type=malformed_json"
	fi

	# Record startup time; capture duration to avoid numeric output in background stdout
	_startup_duration=$(parrot_metrics_end "$START_TIME" "server_startup" "success" 2>&1) || true

	# Keep process alive for test harness
	sleep 5

	parrot_info "MCP server shutting down"
	parrot_log_json "INFO" "MCP server stopped" "component=mcp_server" "action=shutdown"
} &

echo $! >"$PARROT_PID_FILE"
parrot_info "MCP server started with PID: $(cat "$PARROT_PID_FILE")"
