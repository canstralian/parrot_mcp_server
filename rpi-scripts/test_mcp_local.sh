#!/usr/bin/env bash
# =============================================================================
# test_mcp_local.sh - Local MCP Protocol Compliance Test Harness
#
# Description:
#   Runs protocol-level tests for the Parrot MCP Server to verify:
#   - Server startup and shutdown
#   - Valid message processing
#   - Malformed message handling
#   - Logging functionality
#   - Secure IPC operation
#
# Usage:
#   ./test_mcp_local.sh
#
# Security Improvements:
#   - Uses secure IPC directory from common_config.sh
#   - Validates message handling with proper permissions
#   - Tests error conditions and edge cases
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
# =============================================================================

set -euo pipefail

# Source common configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Initialize directories
parrot_init_log_dir
parrot_init_ipc_dir

# Test configuration
SERVER="${SCRIPT_DIR}/start_mcp_server.sh"
STOP="${SCRIPT_DIR}/stop_mcp_server.sh"
TEST_PASSED=0
TEST_FAILED=0

# Helper functions
print_test_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

test_pass() {
    echo "[PASS] $1"
    TEST_PASSED=$((TEST_PASSED + 1))
}

test_fail() {
    echo "[FAIL] $1"
    TEST_FAILED=$((TEST_FAILED + 1))
}

cleanup_test() {
    # Stop server if running
    if [ -f "$PARROT_PID_FILE" ]; then
        "$STOP" >/dev/null 2>&1 || true
    fi

    # Clean up test message files
    rm -f "$PARROT_MCP_INPUT" "$PARROT_MCP_BAD" 2>/dev/null || true
}

# Cleanup on exit
trap cleanup_test EXIT INT TERM

# =============================================================================
# TEST SUITE
# =============================================================================

print_test_header "TEST 1: Server Startup"

# Clean state
cleanup_test

# Start the server
if "$SERVER" >/dev/null 2>&1; then
    sleep 2

    if [ -f "$PARROT_PID_FILE" ]; then
        PID=$(cat "$PARROT_PID_FILE" 2>/dev/null || echo "")

        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            test_pass "Server started successfully (PID: $PID)"
        else
            test_fail "Server PID file exists but process not running"
        fi
    else
        test_fail "Server PID file not created"
    fi
else
    test_fail "Server failed to start"
fi

# =============================================================================

print_test_header "TEST 2: IPC Directory Security"

# Verify IPC directory exists
if [ -d "$PARROT_IPC_DIR" ]; then
    test_pass "IPC directory exists: $PARROT_IPC_DIR"

    # Check permissions (should be 700)
    PERMS=$(stat -c '%a' "$PARROT_IPC_DIR" 2>/dev/null || stat -f '%Lp' "$PARROT_IPC_DIR" 2>/dev/null || echo "000")

    if [ "$PERMS" = "700" ]; then
        test_pass "IPC directory has secure permissions (700)"
    else
        test_fail "IPC directory has insecure permissions ($PERMS, expected 700)"
    fi

    # Verify not using /tmp
    if [[ "$PARROT_IPC_DIR" != "/tmp"* ]]; then
        test_pass "IPC directory is not in /tmp (secure)"
    else
        test_fail "IPC directory is still in /tmp (CRITICAL VULNERABILITY)"
    fi
else
    test_fail "IPC directory does not exist"
fi

# =============================================================================

print_test_header "TEST 3: Valid MCP Message Processing"

# Clean state first
cleanup_test

# Start server
"$SERVER" >/dev/null 2>&1
sleep 1

# Create a valid MCP message after server is running
echo '{"type":"mcp_message","content":"ping"}' > "$PARROT_MCP_INPUT"

# Set secure permissions on message file
chmod 600 "$PARROT_MCP_INPUT" 2>/dev/null || true

# Wait for server to process
sleep 3

# Check logs for expected output
if grep -q 'ping' "$PARROT_SERVER_LOG" 2>/dev/null; then
    test_pass "Valid MCP message processed and logged"
else
    test_fail "Valid MCP message not found in logs"
fi

# Verify message was consumed/removed
if [ ! -f "$PARROT_MCP_INPUT" ]; then
    test_pass "Processed message was cleaned up"
else
    test_fail "Processed message still exists (should be removed)"
fi

# =============================================================================

print_test_header "TEST 4: Malformed MCP Message Handling"

# Clean and restart
cleanup_test
"$SERVER" >/dev/null 2>&1 &
sleep 1

# Create malformed message
echo '{"type":"mcp_message",' > "$PARROT_MCP_BAD"
chmod 600 "$PARROT_MCP_BAD" 2>/dev/null || true

sleep 3

# Check logs for error
if grep -qi 'error\|malformed' "$PARROT_SERVER_LOG" 2>/dev/null; then
    test_pass "Malformed MCP message error logged"
else
    test_fail "Malformed MCP message error not found in logs"
fi

# =============================================================================

print_test_header "TEST 5: Server Shutdown"

# Stop the server
if "$STOP" >/dev/null 2>&1; then
    sleep 1

    if [ ! -f "$PARROT_PID_FILE" ]; then
        test_pass "Server stopped and PID file removed"
    else
        PID=$(cat "$PARROT_PID_FILE" 2>/dev/null || echo "")
        if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
            test_pass "Server process terminated"
            rm -f "$PARROT_PID_FILE"
        else
            test_fail "Server process still running after stop"
        fi
    fi
else
    test_fail "Server stop command failed"
fi

# =============================================================================

print_test_header "TEST 6: Double Start Prevention"

# Start server
cleanup_test
"$SERVER" >/dev/null 2>&1
sleep 2

# Try to start again (should fail)
if ! "$SERVER" >/dev/null 2>&1; then
    test_pass "Double start prevented (server already running)"
else
    test_fail "Double start not prevented (security issue)"
fi

# =============================================================================

print_test_header "TEST 7: Logging Functionality"

# Check that log file exists and has content
if [ -f "$PARROT_SERVER_LOG" ]; then
    test_pass "Server log file exists"

    # Check for proper log format [YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:...]
    if grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[(INFO|WARN|ERROR|DEBUG)\] \[msgid:[0-9]+\]' "$PARROT_SERVER_LOG"; then
        test_pass "Log format is correct"
    else
        test_fail "Log format is incorrect or missing"
    fi
else
    test_fail "Server log file does not exist"
fi

# =============================================================================
# FINAL CLEANUP AND RESULTS
# =============================================================================

cleanup_test

echo ""
echo "=========================================="
echo "TEST RESULTS"
echo "=========================================="
echo "Passed: $TEST_PASSED"
echo "Failed: $TEST_FAILED"
echo "Total:  $((TEST_PASSED + TEST_FAILED))"
echo "=========================================="

if [ "$TEST_FAILED" -eq 0 ]; then
    echo "SUCCESS: All tests passed!"
    exit 0
else
    echo "FAILURE: $TEST_FAILED test(s) failed"
    exit 1
fi
