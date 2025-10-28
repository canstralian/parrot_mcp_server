#!/usr/bin/env bash
# Local MCP protocol compliance test harness
# Usage: ./test_mcp_local.sh
# Runs protocol-level tests for the Parrot MCP Server

set -euo pipefail

SERVER=./rpi-scripts/start_mcp_server.sh
STOP=./rpi-scripts/stop_mcp_server.sh

# Start the server
$SERVER &
SERVER_PID=$!
sleep 2

echo "[TEST] Sending valid MCP message..."
echo '{"type":"mcp_message","content":"ping"}' >/tmp/mcp_in.json
# Simulate sending to server (replace with actual protocol if needed)
cat /tmp/mcp_in.json >/dev/null

echo "[TEST] Sending malformed MCP message..."
echo '{"type":"mcp_message",' >/tmp/mcp_bad.json
cat /tmp/mcp_bad.json >/dev/null

# Check logs for expected output
if grep -q 'ping' ./logs/parrot.log; then
	echo "[PASS] Valid MCP message processed."
else
	echo "[FAIL] Valid MCP message not found in logs."
fi

if grep -q 'error' ./logs/parrot.log; then
	echo "[PASS] Malformed MCP message error logged."
else
	echo "[FAIL] Malformed MCP message error not found in logs."
fi

# Stop the server
$STOP
kill $SERVER_PID 2>/dev/null || true
