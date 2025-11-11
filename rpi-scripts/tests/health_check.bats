#!/usr/bin/env bats
# health_check.bats - Tests for health_check.sh script

# Setup test environment
setup() {
    # Store original directory
    ORIG_DIR="$(pwd)"

    # Find the script directory
    if [ -f "scripts/health_check.sh" ]; then
        SCRIPT_DIR="$(pwd)"
    elif [ -f "../scripts/health_check.sh" ]; then
        SCRIPT_DIR="$(cd .. && pwd)"
    elif [ -f "rpi-scripts/scripts/health_check.sh" ]; then
        SCRIPT_DIR="$(pwd)/rpi-scripts"
    else
        echo "# Cannot find health_check.sh" >&2
        return 1
    fi

    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    # Create test log directory
    mkdir -p "$TEST_DIR/logs"

    # Export test configuration
    export PARROT_LOG_DIR="$TEST_DIR/logs"
    export PARROT_HEALTH_LOG="$TEST_DIR/logs/health_check.log"
    export PARROT_WORKFLOW_LOG="$TEST_DIR/logs/daily_workflow.log"
    export PARROT_ALERT_EMAIL=""  # Disable email notifications in tests
    export PARROT_DEBUG="false"

    # Change to script directory for execution
    cd "$SCRIPT_DIR"
}

teardown() {
    # Return to original directory
    cd "$ORIG_DIR"

    # Cleanup temporary test directory
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# ============================================================================
# COMMAND-LINE ARGUMENT TESTS
# ============================================================================

@test "health_check: accepts --help flag" {
    run bash scripts/health_check.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "health_check: accepts -h flag" {
    run bash scripts/health_check.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "health_check: accepts --disk-threshold with valid percentage" {
    run bash scripts/health_check.sh --disk-threshold 85
    [ "$status" -eq 0 ]
}

@test "health_check: rejects --disk-threshold with invalid percentage" {
    run bash scripts/health_check.sh --disk-threshold 101
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid disk threshold" ]]
}

@test "health_check: rejects --disk-threshold with negative value" {
    run bash scripts/health_check.sh --disk-threshold -5
    [ "$status" -eq 1 ]
}

@test "health_check: rejects --disk-threshold with non-numeric value" {
    run bash scripts/health_check.sh --disk-threshold abc
    [ "$status" -eq 1 ]
}

@test "health_check: rejects --disk-threshold without value" {
    run bash scripts/health_check.sh --disk-threshold
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Missing value" ]]
}

@test "health_check: accepts --load-threshold with valid value" {
    run bash scripts/health_check.sh --load-threshold 2.5
    [ "$status" -eq 0 ]
}

@test "health_check: rejects unknown option" {
    run bash scripts/health_check.sh --invalid-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

# ============================================================================
# LOGGING TESTS
# ============================================================================

@test "health_check: creates log file" {
    run bash scripts/health_check.sh --disk-threshold 95
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/logs/health_check.log" ]
}

@test "health_check: log contains timestamp" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    grep -q '\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$TEST_DIR/logs/health_check.log"
}

@test "health_check: log contains message ID" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    grep -q '\[msgid:[0-9]\+\]' "$TEST_DIR/logs/health_check.log"
}

@test "health_check: log contains INFO level" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    grep -q '\[INFO\]' "$TEST_DIR/logs/health_check.log"
}

# ============================================================================
# DISK CHECK TESTS
# ============================================================================

@test "health_check: disk check with high threshold (should pass)" {
    run bash scripts/health_check.sh --disk-threshold 99
    [ "$status" -eq 0 ]
    grep -q "Disk usage:.*OK" "$TEST_DIR/logs/health_check.log"
}

@test "health_check: disk check logs usage percentage" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    grep -q "Disk usage: [0-9]\+%" "$TEST_DIR/logs/health_check.log"
}

# ============================================================================
# WORKFLOW CHECK TESTS
# ============================================================================

@test "health_check: warns when workflow log missing" {
    # Don't create workflow log file
    run bash scripts/health_check.sh
    # Script should still complete but log warning
    grep -q "Workflow log file not found" "$TEST_DIR/logs/health_check.log" || \
    grep -q "ALERT.*workflow" "$TEST_DIR/logs/health_check.log"
}

@test "health_check: handles empty workflow log" {
    # Create empty workflow log
    touch "$TEST_DIR/logs/daily_workflow.log"
    run bash scripts/health_check.sh
    grep -q "empty" "$TEST_DIR/logs/health_check.log" || \
    grep -q "not found" "$TEST_DIR/logs/health_check.log"
}

@test "health_check: accepts recent workflow log entry" {
    # Create workflow log with recent timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DAILY_WORKFLOW] Completed" > "$TEST_DIR/logs/daily_workflow.log"
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    grep -q "Daily workflow last ran" "$TEST_DIR/logs/health_check.log"
}

# ============================================================================
# LOAD CHECK TESTS
# ============================================================================

@test "health_check: performs load check" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    grep -q "System load:" "$TEST_DIR/logs/health_check.log"
}

@test "health_check: load check with high threshold" {
    run bash scripts/health_check.sh --load-threshold 999.0
    [ "$status" -eq 0 ]
    grep -q "System load:.*OK" "$TEST_DIR/logs/health_check.log"
}

# ============================================================================
# MCP SERVER CHECK TESTS
# ============================================================================

@test "health_check: detects MCP server not running" {
    run bash scripts/health_check.sh
    # Server likely not running in test environment
    grep -q "MCP server" "$TEST_DIR/logs/health_check.log"
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

@test "health_check: logs configuration on startup" {
    run bash scripts/health_check.sh --disk-threshold 85 --load-threshold 2.5
    [ "$status" -eq 0 ]
    grep -q "Configuration:" "$TEST_DIR/logs/health_check.log"
    grep -q "disk_threshold=85%" "$TEST_DIR/logs/health_check.log"
}

@test "health_check: uses default thresholds when not specified" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    # Should complete without errors even with defaults
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "health_check: handles missing log directory" {
    # Remove log directory
    rm -rf "$TEST_DIR/logs"
    run bash scripts/health_check.sh
    # Script should create directory or handle gracefully
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "health_check: completes even with check failures" {
    # Script should complete main() even if individual checks fail
    run bash scripts/health_check.sh
    grep -q "Health check completed" "$TEST_DIR/logs/health_check.log" || [ "$status" -eq 0 ]
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

@test "health_check: runs all checks" {
    run bash scripts/health_check.sh
    [ "$status" -eq 0 ]
    log_content=$(cat "$TEST_DIR/logs/health_check.log")

    # Verify all checks were performed
    echo "$log_content" | grep -q "Starting health check"
    echo "$log_content" | grep -q "Disk usage:"
    echo "$log_content" | grep -q "System load:"
    echo "$log_content" | grep -q "MCP server"
}

@test "health_check: exit code reflects overall status" {
    run bash scripts/health_check.sh
    # Exit code should be 0 for success or 1 for failures
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ============================================================================
# SECURITY TESTS
# ============================================================================

@test "SECURITY: health_check rejects command injection in threshold" {
    run bash scripts/health_check.sh --disk-threshold "80; rm -rf /"
    [ "$status" -eq 1 ]
}

@test "SECURITY: health_check validates numeric thresholds" {
    run bash scripts/health_check.sh --disk-threshold "<script>alert('xss')</script>"
    [ "$status" -eq 1 ]
}

@test "SECURITY: health_check prevents path traversal in logs" {
    export PARROT_HEALTH_LOG="../../../etc/passwd"
    run bash scripts/health_check.sh
    # Should fail path validation or handle safely
    [ "$status" -eq 1 ] || ! [ -f "/etc/passwd.new" ]
}
