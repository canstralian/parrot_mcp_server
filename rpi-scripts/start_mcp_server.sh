#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling

# Resolve script directory for proper path handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up paths relative to script directory
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/parrot.log"
PID_FILE="${LOG_DIR}/mcp_server.pid"
MSGID=$(date +%s%N)

{
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] MCP server started (stub)"
	# Simulate handling a valid MCP message
	if [ -f /tmp/mcp_in.json ]; then
		if grep -q '"content":"ping"' /tmp/mcp_in.json; then
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] MCP message received: ping"
		else
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] MCP message file present but no ping content"
		fi
	else
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] No valid MCP message file found"
	fi
	# Simulate handling a malformed MCP message
	if [ -f /tmp/mcp_bad.json ]; then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Malformed MCP message received"
	fi
	# Keep process alive for test harness
	sleep 5
} >>"$LOG" 2>&1 &
echo $! >"$PID_FILE"
