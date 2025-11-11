#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# stop_mcp_server.sh
#
# Description:
#   This script stops the Parrot MCP Server by terminating the process whose PID
#   is stored in the PID file. It also cleans up named pipes used for IPC.
#   All actions and errors are logged with a timestamp and unique message ID.
#
# Usage:
#   ./stop_mcp_server.sh
#
# Behavior:
#   - Checks for the existence of the PID file.
#   - If found, attempts to kill the process and removes the PID file.
#   - Cleans up named pipes used for IPC.
#   - Logs success or failure to the log file.
#   - If the PID file is missing, logs a warning and exits with an error.
#
# Log Format:
#   [YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:UNIQUE_ID] Message
#
# Exit Codes:
#   0 - Success
#   1 - Failure (e.g., PID file missing or process could not be killed)
# -----------------------------------------------------------------------------

set -euo pipefail

# Load common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

if [ -f "$PARROT_PID_FILE" ]; then
	PID=$(cat "$PARROT_PID_FILE")
	if kill "$PID" 2>/dev/null; then
		rm -f "$PARROT_PID_FILE"
		parrot_info "MCP server stopped (pid $PID)"
		
		# Clean up named pipes
		parrot_cleanup_pipes "$PARROT_MCP_INPUT_PIPE" "$PARROT_MCP_OUTPUT_PIPE"
		
		echo "MCP server stopped successfully."
	else
		parrot_error "Failed to kill MCP server process (pid $PID)"
		echo "Failed to stop MCP server. Process may have already exited."
		exit 1
	fi
else
	parrot_warn "No MCP server PID file found on stop"
	echo "No MCP server PID file found."
	
	# Try to clean up pipes anyway
	parrot_cleanup_pipes "$PARROT_MCP_INPUT_PIPE" "$PARROT_MCP_OUTPUT_PIPE"
	
	exit 1
fi
