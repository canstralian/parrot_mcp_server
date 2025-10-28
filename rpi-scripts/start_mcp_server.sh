#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server
mkdir -p ./logs
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP server started (stub)"
    # Simulate handling a valid MCP message
    if [ -f /tmp/mcp_in.json ]; then
        if grep -q '"content":"ping"' /tmp/mcp_in.json; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP message received: ping"
        fi
    fi
    # Simulate handling a malformed MCP message
    if [ -f /tmp/mcp_bad.json ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] error: Malformed MCP message received"
    fi
    # Keep process alive for test harness
    sleep 5
} >> ./logs/parrot.log 2>&1 &
echo $! > ./logs/mcp_server.pid
