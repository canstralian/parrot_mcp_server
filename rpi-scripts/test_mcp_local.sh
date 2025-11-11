#!/usr/bin/env bash
# Local MCP protocol compliance test harness
# Usage: ./test_mcp_local.sh
# Runs protocol-level tests for the Parrot MCP Server using secure named pipes

set -euo pipefail

# Load common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

SERVER=./start_mcp_server.sh
STOP=./stop_mcp_server.sh

# Start the server in background
$SERVER &
SERVER_PID=$!

# Wait for pipes to be created
echo "[TEST] Waiting for server to initialize..."
for _ in {1..10}; do
    if [ -p "$PARROT_MCP_INPUT_PIPE" ] && [ -p "$PARROT_MCP_OUTPUT_PIPE" ]; then
        echo "[TEST] Server ready."
        break
    fi
    sleep 0.5
done

if [ ! -p "$PARROT_MCP_INPUT_PIPE" ]; then
    echo "[FAIL] Input pipe not created"
    kill "$SERVER_PID" 2>/dev/null || true
    exit 1
fi

echo "[TEST] Sending valid MCP message..."
# Send message to input pipe in background and read response
(echo '{"type":"mcp_message","content":"ping"}' > "$PARROT_MCP_INPUT_PIPE") &
SEND_PID=$!

# Read response with timeout
if timeout 2 cat "$PARROT_MCP_OUTPUT_PIPE" > /dev/null 2>&1; then
    echo "[TEST] Response received from server."
else
    echo "[WARN] No response received (timeout)."
fi
wait "$SEND_PID" 2>/dev/null || true

echo "[TEST] Sending malformed MCP message..."
(echo '{"type":"mcp_message",' > "$PARROT_MCP_INPUT_PIPE") &
SEND_PID=$!
sleep 1
wait "$SEND_PID" 2>/dev/null || true

# Give server time to process
sleep 1

# Check logs for expected output
echo "[TEST] Checking logs..."
if grep -q 'ping' "$PARROT_SERVER_LOG" 2>/dev/null; then
	echo "[PASS] Valid MCP message processed."
else
	echo "[FAIL] Valid MCP message not found in logs."
fi

if grep -qi 'error.*malformed' "$PARROT_SERVER_LOG" 2>/dev/null; then
	echo "[PASS] Malformed MCP message error logged."
else
	echo "[FAIL] Malformed MCP message error not found in logs."
fi

# Stop the server
echo "[TEST] Stopping server..."
$STOP
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

echo "[TEST] Test suite completed."
