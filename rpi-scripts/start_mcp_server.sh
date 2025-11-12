#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling

set -euo pipefail

# Get script directory and source common config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Start server in background
{
	# Track startup time for metrics
	START_TIME=$(parrot_metrics_start)
	
	parrot_info "MCP server starting"
	parrot_log_json "INFO" "MCP server started" "component=mcp_server" "action=startup"
	parrot_audit_log "server_start" "mcp_server" "success"
	
	# Simulate handling a valid MCP message
	if [ -f /tmp/mcp_in.json ]; then
		if grep -q '"content":"ping"' /tmp/mcp_in.json; then
			MSG_START=$(parrot_metrics_start)
			parrot_info "MCP message received: ping"
			parrot_log_json "INFO" "MCP message processed" "message_type=ping" "status=success"
			parrot_metrics_end "$MSG_START" "mcp_message_process" "success" "message_type=ping"
		else
			parrot_warn "MCP message file present but no ping content"
			parrot_log_json "WARN" "Invalid MCP message content" "status=invalid"
		fi
	else
		parrot_warn "No valid MCP message file found"
	fi
	
	# Simulate handling a malformed MCP message
	if [ -f /tmp/mcp_bad.json ]; then
		parrot_error "Malformed MCP message received"
		parrot_log_json "ERROR" "Malformed MCP message" "status=error" "error_type=malformed_json"
		parrot_audit_log "message_error" "/tmp/mcp_bad.json" "error" "error_type=malformed_json"
	fi
	
	# Record startup time
	parrot_metrics_end "$START_TIME" "server_startup" "success"
	
	# Keep process alive for test harness
	sleep 5
	
	parrot_info "MCP server shutting down"
	parrot_log_json "INFO" "MCP server stopped" "component=mcp_server" "action=shutdown"
} >>"$PARROT_SERVER_LOG" 2>&1 &

echo $! >"$PARROT_PID_FILE"
parrot_info "MCP server started with PID: $(cat "$PARROT_PID_FILE")"
