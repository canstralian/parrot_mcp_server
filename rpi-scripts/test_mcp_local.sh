#!/usr/bin/env bash
# Local MCP protocol compliance test harness
# Usage: ./test_mcp_local.sh
# Runs protocol-level tests for the Parrot MCP Server

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load common configuration
# shellcheck source=./common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

SERVER="${SCRIPT_DIR}/start_mcp_server.sh"
STOP="${SCRIPT_DIR}/stop_mcp_server.sh"

# Cleanup function
cleanup() {
    parrot_debug "Cleaning up test artifacts..."
    "$STOP" 2>/dev/null || true
    rm -f "$PARROT_MCP_INPUT" "$PARROT_MCP_BAD" 2>/dev/null || true
}

# Set up trap for cleanup on exit
trap cleanup EXIT

# Initialize test counters
TESTS_RUN=0
TESTS_PASSED=0

run_test() {
    local test_name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))

    echo "[TEST $TESTS_RUN] $test_name"
    if "$@"; then
        echo "[PASS] $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "[FAIL] $test_name"
        return 1
    fi
}

test_valid_message() {
    # Start the server
    "$SERVER" || {
        parrot_error "Failed to start MCP server"
        return 1
    }
    sleep 2

    # Send valid MCP message
    echo '{"type":"mcp_message","content":"ping"}' > "$PARROT_MCP_INPUT"

    # Wait for processing
    sleep 1

    # Check logs for expected output
    if grep -q 'ping' "$PARROT_SERVER_LOG" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

test_malformed_message() {
    # Ensure server is running
    if ! pgrep -f "start_mcp_server.sh" >/dev/null; then
        "$SERVER" || {
            parrot_error "Failed to start MCP server"
            return 1
        }
        sleep 2
    fi

    # Send malformed MCP message
    echo '{"type":"mcp_message",' > "$PARROT_MCP_BAD"

    # Wait for processing
    sleep 1

    # Check logs for error (case-insensitive)
    if grep -i 'error' "$PARROT_SERVER_LOG" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Main test execution
parrot_info "Starting MCP protocol compliance tests"

run_test "Valid MCP message processing" test_valid_message
run_test "Malformed MCP message error logging" test_malformed_message

# Print summary
echo ""
echo "=========================================="
echo "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
echo "=========================================="

if [ "$TESTS_PASSED" -eq "$TESTS_RUN" ]; then
    parrot_info "All tests passed!"
    exit 0
else
    parrot_error "Some tests failed: $((TESTS_RUN - TESTS_PASSED)) failed"
    exit 1
fi
