#!/usr/bin/env bash
# Stop the Parrot MCP Server (minimal stub)
LOG=./logs/parrot.log
MSGID=$(date +%s%N)
if [ -f ./logs/mcp_server.pid ]; then
    PID=$(cat ./logs/mcp_server.pid)
    if kill "$PID" 2>/dev/null; then
        rm -f ./logs/mcp_server.pid
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] MCP server stopped (pid $PID)" >> "$LOG"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Failed to kill MCP server process (pid $PID)" >> "$LOG"
        exit 1
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] No MCP server PID file found on stop" >> "$LOG"
    echo "No MCP server PID file found."
    exit 1
fi
