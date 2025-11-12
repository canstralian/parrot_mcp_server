#!/usr/bin/env bash
# Stop the Parrot MCP Server
# Stops the server process using PID file

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
# shellcheck source=common_config.sh disable=SC1091
source "${SCRIPT_DIR}/common_config.sh"

# Set log file
export PARROT_CURRENT_LOG="$PARROT_SERVER_LOG"

if [ -f "$PARROT_PID_FILE" ]; then
	PID=$(cat "$PARROT_PID_FILE")
	
	# Check if process is still running
	if ! ps -p "$PID" > /dev/null 2>&1; then
		parrot_warn "MCP server process (pid $PID) is not running"
		rm -f "$PARROT_PID_FILE"
		exit 0
	fi
	
	if kill "$PID" 2>/dev/null; then
		rm -f "$PARROT_PID_FILE"
		parrot_info "MCP server stopped (pid $PID)"
	else
		parrot_error "Failed to kill MCP server process (pid $PID)"
		exit 1
	fi
else
	parrot_warn "No MCP server PID file found"
	echo "No MCP server PID file found."
	# Don't exit with error if server isn't running (not a real error)
	exit 0
fi
