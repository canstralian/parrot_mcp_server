#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling
mkdir -p ./logs
LOG=./logs/parrot.log
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
echo $! >./logs/mcp_server.pid
