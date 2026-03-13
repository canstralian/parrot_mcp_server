#!/usr/bin/env bats
# stop_mcp_server.bats - Tests for stop_mcp_server.sh
#
# The script uses paths relative to its CWD (./logs/).
# Each test runs from a fresh temp directory that mirrors the expected layout.

STOP_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/stop_mcp_server.sh"

setup() {
    # Create a temp directory that acts as the working directory for the script
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/logs"

    # Record original CWD to restore in teardown
    ORIG_DIR="$(pwd)"
    cd "$TEST_DIR"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# ============================================================================
# PID FILE MISSING
# ============================================================================

@test "stop_mcp_server: exits with code 1 when PID file is missing" {
    run bash "$STOP_SCRIPT"
    [ "$status" -eq 1 ]
}

@test "stop_mcp_server: prints 'No MCP server PID file found' when PID file missing" {
    run bash "$STOP_SCRIPT"
    [[ "$output" == *"No MCP server PID file found"* ]]
}

@test "stop_mcp_server: logs WARN entry when PID file is missing" {
    run bash "$STOP_SCRIPT"
    [ -f "$TEST_DIR/logs/parrot.log" ]
    grep -q '\[WARN\]' "$TEST_DIR/logs/parrot.log"
}

@test "stop_mcp_server: log entry contains expected message when PID file missing" {
    bash "$STOP_SCRIPT" || true
    grep -q "No MCP server PID file found on stop" "$TEST_DIR/logs/parrot.log"
}

# ============================================================================
# VALID PID — SUCCESSFUL STOP
# ============================================================================

@test "stop_mcp_server: exits with code 0 when process is successfully killed" {
    # Start a long-running background process to kill
    sleep 300 &
    SLEEP_PID=$!
    echo "$SLEEP_PID" > "$TEST_DIR/logs/mcp_server.pid"

    run bash "$STOP_SCRIPT"
    [ "$status" -eq 0 ]

    # Clean up in case the test failed before kill
    kill "$SLEEP_PID" 2>/dev/null || true
}

@test "stop_mcp_server: removes PID file after successful stop" {
    sleep 300 &
    SLEEP_PID=$!
    echo "$SLEEP_PID" > "$TEST_DIR/logs/mcp_server.pid"

    bash "$STOP_SCRIPT"
    [ ! -f "$TEST_DIR/logs/mcp_server.pid" ]

    kill "$SLEEP_PID" 2>/dev/null || true
}

@test "stop_mcp_server: logs INFO entry after successful stop" {
    sleep 300 &
    SLEEP_PID=$!
    echo "$SLEEP_PID" > "$TEST_DIR/logs/mcp_server.pid"

    bash "$STOP_SCRIPT"
    grep -q '\[INFO\]' "$TEST_DIR/logs/parrot.log"

    kill "$SLEEP_PID" 2>/dev/null || true
}

@test "stop_mcp_server: log entry includes PID on successful stop" {
    sleep 300 &
    SLEEP_PID=$!
    echo "$SLEEP_PID" > "$TEST_DIR/logs/mcp_server.pid"

    bash "$STOP_SCRIPT"
    grep -q "pid $SLEEP_PID" "$TEST_DIR/logs/parrot.log"

    kill "$SLEEP_PID" 2>/dev/null || true
}

# ============================================================================
# STALE PID — PROCESS NO LONGER EXISTS
# ============================================================================

@test "stop_mcp_server: exits with code 1 when PID does not exist" {
    # Use a PID that is guaranteed not to exist
    echo "999999999" > "$TEST_DIR/logs/mcp_server.pid"

    run bash "$STOP_SCRIPT"
    [ "$status" -eq 1 ]
}

@test "stop_mcp_server: logs ERROR when kill fails" {
    echo "999999999" > "$TEST_DIR/logs/mcp_server.pid"

    bash "$STOP_SCRIPT" || true
    grep -q '\[ERROR\]' "$TEST_DIR/logs/parrot.log"
}

@test "stop_mcp_server: PID file is preserved when kill fails" {
    echo "999999999" > "$TEST_DIR/logs/mcp_server.pid"

    bash "$STOP_SCRIPT" || true
    # PID file should still exist since the kill did not succeed
    [ -f "$TEST_DIR/logs/mcp_server.pid" ]
}

# ============================================================================
# LOG FORMAT
# ============================================================================

@test "stop_mcp_server: log entry includes timestamp" {
    # Trigger any code path that writes to the log
    bash "$STOP_SCRIPT" || true
    grep -qE '\[20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' \
        "$TEST_DIR/logs/parrot.log"
}

@test "stop_mcp_server: log entry includes msgid field" {
    bash "$STOP_SCRIPT" || true
    grep -q '\[msgid:[0-9]\+\]' "$TEST_DIR/logs/parrot.log"
}

@test "stop_mcp_server: creates log file on first invocation" {
    [ ! -f "$TEST_DIR/logs/parrot.log" ]
    bash "$STOP_SCRIPT" || true
    [ -f "$TEST_DIR/logs/parrot.log" ]
}
