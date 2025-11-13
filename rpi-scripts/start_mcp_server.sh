#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/common_config.sh" ]; then
    # shellcheck source=./common_config.sh disable=SC1091
    source "${SCRIPT_DIR}/common_config.sh"
else
    echo "ERROR: Cannot find common_config.sh" >&2
    exit 1
fi

# Set script-specific log file (exported for use by parrot_log functions)
export PARROT_CURRENT_LOG="$PARROT_SERVER_LOG"

# Initialize log directory
parrot_init_log_dir

# Start server in background
{
	parrot_info "MCP server started (stub)"
	
	# Simulate handling a valid MCP message
	if [ -f "$PARROT_MCP_INPUT" ]; then
		if grep -q '"content":"ping"' "$PARROT_MCP_INPUT"; then
			parrot_info "MCP message received: ping"
		else
			parrot_warn "MCP message file present but no ping content"
		fi
	else
		parrot_warn "No valid MCP message file found"
	fi
	
	# Simulate handling a malformed MCP message
	if [ -f "$PARROT_MCP_BAD" ]; then
		parrot_error "Malformed MCP message received"
	fi
	
	# Keep process alive for test harness
	sleep 5
} >>"$PARROT_SERVER_LOG" 2>&1 &

echo $! >"$PARROT_PID_FILE"
