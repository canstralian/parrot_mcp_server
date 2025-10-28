#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# stop_mcp_server.sh
#
# Description:
#   This script stops the Parrot MCP Server by terminating the process whose PID
#   is stored in ./logs/mcp_server.pid. It logs all actions and errors to
#   ./logs/parrot.log with a timestamp and unique message ID.
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
# Log Format:
#   [YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:UNIQUE_ID] Message
#
# Exit Codes:
#   0 - Success
#   1 - Failure (e.g., PID file missing or process could not be killed)
# -----------------------------------------------------------------------------
# Stop the Parrot MCP Server (minimal stub)
LOG=./logs/parrot.log
MSGID=$(date +%s%N)
if [ -f ./logs/mcp_server.pid ]; then
	PID=$(cat ./logs/mcp_server.pid)
	if kill "$PID" 2>/dev/null; then
		rm -f ./logs/mcp_server.pid
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] MCP server stopped (pid $PID)" >>"$LOG"
	else
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Failed to kill MCP server process (pid $PID)" >>"$LOG"
		exit 1
	fi
else
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] No MCP server PID file found on stop" >>"$LOG"
	echo "No MCP server PID file found."
	exit 1
fi
