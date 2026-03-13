#!/usr/bin/env bash
# Local MCP protocol compliance test harness
# Usage: ./test_mcp_local.sh
# Runs protocol-level tests for the Parrot MCP Server

set -euo pipefail

# Get the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")"

# Load centralized config so PARROT_IPC_DIR / PARROT_MCP_INPUT etc. are defined,
# and avoid writing to world-writable /tmp with predictable filenames.
if [ -f "./common_config.sh" ]; then
    # shellcheck source=./common_config.sh disable=SC1091
    source "./common_config.sh"
else
    # Fallback: honour env override or use /tmp only as last resort
    PARROT_IPC_DIR="${PARROT_IPC_DIR:-/tmp}"
fi
MCP_IN="${PARROT_MCP_INPUT:-${PARROT_IPC_DIR}/mcp_in.json}"
MCP_BAD="${PARROT_MCP_BAD:-${PARROT_IPC_DIR}/mcp_bad.json}"

SERVER="./start_mcp_server.sh"
STOP="./stop_mcp_server.sh"

# Start the server
$SERVER &
SERVER_PID=$!
sleep 2

echo "[TEST] Sending valid MCP message..."
echo '{"type":"mcp_message","content":"ping"}' >"$MCP_IN"
# Simulate sending to server (replace with actual protocol if needed)
cat "$MCP_IN" >/dev/null

echo "[TEST] Sending malformed MCP message..."
echo '{"type":"mcp_message",' >"$MCP_BAD"
cat "$MCP_BAD" >/dev/null

# Check logs for expected output
if grep -q 'ping' ./logs/parrot.log 2>/dev/null; then
	echo "[PASS] Valid MCP message processed."
else
	echo "[FAIL] Valid MCP message not found in logs."
fi

if grep -iq 'error' ./logs/parrot.log 2>/dev/null; then
	echo "[PASS] Malformed MCP message error logged."
else
	echo "[FAIL] Malformed MCP message error not found in logs."
fi

# Stop the server
$STOP || true
kill $SERVER_PID 2>/dev/null || true
