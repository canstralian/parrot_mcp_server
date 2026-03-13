#!/usr/bin/env bash
# Local MCP protocol compliance test harness
# Usage: ./test_mcp_local.sh
# Runs protocol-level tests for the Parrot MCP Server

set -euo pipefail

# Get the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")"

SERVER="./start_mcp_server.sh"
STOP="./stop_mcp_server.sh"

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

# ---------------------------------------------------------------------------
# tools/list — verify all orchestration tool names are advertised
# ---------------------------------------------------------------------------
echo "[TEST] Verifying tools/list advertises all orchestration tools..."

TOOLS_REQUEST='{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
TOOLS_RESPONSE=$(echo "$TOOLS_REQUEST" | parrot-mcp 2>/dev/null || true)

REQUIRED_TOOLS=(
    "register_agent"
    "deregister_agent"
    "submit_task"
    "complete_task"
    "submit_workflow"
    "agent_heartbeat"
    "orchestrator_status"
)

TOOLS_PASS=true
for tool in "${REQUIRED_TOOLS[@]}"; do
    if echo "$TOOLS_RESPONSE" | grep -q "\"$tool\""; then
        echo "[PASS] Tool advertised: $tool"
    else
        echo "[FAIL] Tool NOT advertised: $tool"
        TOOLS_PASS=false
    fi
done

if $TOOLS_PASS; then
    echo "[PASS] All orchestration tools present in tools/list response."
else
    echo "[FAIL] Some orchestration tools missing from tools/list response."
fi

# Stop the server
$STOP || true
kill $SERVER_PID 2>/dev/null || true
