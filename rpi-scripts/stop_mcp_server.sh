#!/usr/bin/env bash
# Stop the Parrot MCP Server (minimal stub)
if [ -f ./logs/mcp_server.pid ]; then
    kill $(cat ./logs/mcp_server.pid) 2>/dev/null || true
    rm -f ./logs/mcp_server.pid
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP server stopped" >> ./logs/parrot.log
else
    echo "No MCP server PID file found."
fi
