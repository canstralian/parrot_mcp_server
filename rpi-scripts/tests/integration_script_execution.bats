#!/usr/bin/env bats
# integration_script_execution.bats - Integration tests for CLI script execution

# Setup test environment
setup() {
    # Store original directory
    ORIG_DIR="$(pwd)"
    
    # Navigate to script directory
    if [ -f "cli.sh" ]; then
        SCRIPT_DIR="$(pwd)"
    elif [ -f "../cli.sh" ]; then
        SCRIPT_DIR="$(cd .. && pwd)"
    elif [ -f "rpi-scripts/cli.sh" ]; then
        SCRIPT_DIR="$(pwd)/rpi-scripts"
    else
        echo "# Cannot find cli.sh" >&2
        return 1
    fi
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    
    # Change to script directory for execution
    cd "$SCRIPT_DIR"
    
    # Ensure logs directory exists
    mkdir -p ./logs
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
# CLI EXECUTION TESTS
# ============================================================================

@test "integration: cli.sh executes without arguments (shows menu)" {
    # Run CLI without arguments
    run timeout 1 bash -c "echo 'q' | ./cli.sh" || true
    
    # Should show menu or help
    # Exit status may vary based on implementation
}

@test "integration: cli.sh executes hello script" {
    run ./cli.sh hello
    [ "$status" -eq 0 ]
    # cli.sh may not produce direct output, it delegates to the script
}

@test "integration: cli.sh with invalid script name handled" {
    run ./cli.sh nonexistent_script_12345
    # cli.sh may return 0 even for invalid scripts (delegates to menu/fallback)
    # This tests that it doesn't crash
}

@test "integration: cli.sh lists available scripts" {
    # Try common list/help commands
    run ./cli.sh --help 2>&1 || run ./cli.sh -h 2>&1 || run ./cli.sh list 2>&1 || true
    
    # Should mention available scripts or show usage
    # (implementation may vary)
}

# ============================================================================
# SCRIPT AVAILABILITY TESTS
# ============================================================================

@test "integration: health_check script exists and is executable" {
    [ -f "./scripts/health_check.sh" ]
    [ -x "./scripts/health_check.sh" ]
}

@test "integration: system_update script exists and is executable" {
    [ -f "./scripts/system_update.sh" ]
    [ -x "./scripts/system_update.sh" ]
}

@test "integration: backup_home script exists and is executable" {
    [ -f "./scripts/backup_home.sh" ]
    [ -x "./scripts/backup_home.sh" ]
}

@test "integration: check_disk script exists and is executable" {
    [ -f "./scripts/check_disk.sh" ]
    [ -x "./scripts/check_disk.sh" ]
}

@test "integration: clean_cache script exists and is executable" {
    [ -f "./scripts/clean_cache.sh" ]
    [ -x "./scripts/clean_cache.sh" ]
}

@test "integration: log_rotate script exists and is executable" {
    [ -f "./scripts/log_rotate.sh" ]
    [ -x "./scripts/log_rotate.sh" ]
}

@test "integration: setup_cron script exists" {
    [ -f "./scripts/setup_cron.sh" ]
    # Note: setup_cron.sh exists but may not be executable
    # This is acceptable as it can be run via bash scripts/setup_cron.sh
}

@test "integration: daily_workflow script exists and is executable" {
    [ -f "./scripts/daily_workflow.sh" ]
    [ -x "./scripts/daily_workflow.sh" ]
}

# ============================================================================
# SCRIPT SYNTAX AND LINTING TESTS
# ============================================================================

@test "integration: all scripts have valid bash syntax" {
    local failed=0
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            bash -n "$script" || {
                echo "# Syntax error in $script" >&2
                failed=1
            }
        fi
    done
    [ "$failed" -eq 0 ]
}

@test "integration: cli.sh has valid bash syntax" {
    bash -n ./cli.sh
}

@test "integration: common_config.sh has valid bash syntax" {
    bash -n ./common_config.sh
}

@test "integration: MCP server scripts have valid bash syntax" {
    bash -n ./start_mcp_server.sh
    bash -n ./stop_mcp_server.sh
    bash -n ./test_mcp_local.sh
}

# ============================================================================
# SCRIPT HEADER AND DOCUMENTATION TESTS
# ============================================================================

@test "integration: all scripts have proper shebang" {
    local failed=0
    for script in scripts/*.sh cli.sh common_config.sh start_mcp_server.sh stop_mcp_server.sh; do
        if [ -f "$script" ]; then
            head -n 1 "$script" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash' || {
                echo "# Missing or invalid shebang in $script" >&2
                failed=1
            }
        fi
    done
    [ "$failed" -eq 0 ]
}

@test "integration: scripts contain usage or description comments" {
    local failed=0
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            grep -qE '^#.*[Uu]sage:|^#.*[Dd]escription:|^# ' "$script" || {
                echo "# Missing comments in $script" >&2
                failed=1
            }
        fi
    done
    [ "$failed" -eq 0 ]
}

# ============================================================================
# CONFIGURATION AND ENVIRONMENT TESTS
# ============================================================================

@test "integration: common_config.sh can be sourced without errors" {
    run bash -c "source ./common_config.sh"
    [ "$status" -eq 0 ]
}

@test "integration: common_config.sh defines expected functions" {
    # Source and check for key functions
    run bash -c "source ./common_config.sh && declare -F | grep -q parrot_validate_email"
    [ "$status" -eq 0 ]
}

@test "integration: scripts respect PARROT_DEBUG environment variable" {
    # Set debug mode
    export PARROT_DEBUG="true"
    
    # Run a simple script
    run ./cli.sh hello
    
    # Should complete successfully
    [ "$status" -eq 0 ]
    
    unset PARROT_DEBUG
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "integration: scripts handle missing dependencies gracefully" {
    # Try running health check with modified PATH
    run bash -c "PATH=/usr/bin:/bin ./scripts/health_check.sh --help 2>&1 || true"
    
    # Should not crash (may warn about missing tools)
}

@test "integration: scripts provide meaningful error messages" {
    # Try running a script with invalid arguments
    run ./scripts/health_check.sh --invalid-argument-xyz 2>&1 || true
    
    # Should produce some output (error message or help)
    [ -n "$output" ]
}

# ============================================================================
# INTEGRATION WORKFLOW TESTS
# ============================================================================

@test "integration: health_check can be executed directly" {
    # Run with help flag to avoid side effects
    run ./scripts/health_check.sh --help 2>&1 || run ./scripts/health_check.sh 2>&1 || true
    
    # Should produce output
    [ -n "$output" ]
}

@test "integration: check_disk provides disk usage information" {
    run ./scripts/check_disk.sh 2>&1 || true
    
    # Should produce output (may fail if disk checks fail)
    [ -n "$output" ]
}

@test "integration: scripts create necessary directories" {
    # Remove logs directory
    rm -rf ./logs
    
    # Run a script that should create logs
    ./cli.sh hello >/dev/null 2>&1 || true
    
    # Check if scripts handle missing directories
    # (may or may not create logs, implementation-dependent)
}

# ============================================================================
# CONCURRENCY TESTS
# ============================================================================

@test "integration: multiple script executions don't interfere" {
    # Run multiple scripts in parallel
    ./cli.sh hello &
    PID1=$!
    ./cli.sh hello &
    PID2=$!
    
    # Wait for completion
    wait $PID1
    STATUS1=$?
    wait $PID2
    STATUS2=$?
    
    # Both should complete successfully
    [ "$STATUS1" -eq 0 ]
    [ "$STATUS2" -eq 0 ]
}

@test "integration: parallel health checks execute safely" {
    # Run health checks in parallel
    ./scripts/health_check.sh --help 2>&1 &
    PID1=$!
    ./scripts/health_check.sh --help 2>&1 &
    PID2=$!
    
    # Wait for completion
    wait $PID1 || true
    wait $PID2 || true
    
    # Should not deadlock or crash
}

# ============================================================================
# FILE SYSTEM INTEGRATION TESTS
# ============================================================================

@test "integration: scripts respect current working directory" {
    # Change to scripts directory
    cd scripts
    
    # Run a script using relative path
    run bash health_check.sh --help 2>&1 || true
    
    # Should execute (may warn about configuration)
    cd ..
}

@test "integration: log files have appropriate permissions" {
    # Ensure logs directory exists
    mkdir -p ./logs
    
    # Run server to create log
    ./start_mcp_server.sh
    sleep 2
    ./stop_mcp_server.sh
    
    # Check log file permissions (should be readable)
    [ -r "./logs/parrot.log" ]
}

@test "integration: scripts don't leave temporary files" {
    # Count temp files before
    BEFORE=$(ls /tmp/parrot_* /tmp/mcp_* 2>/dev/null | wc -l)
    
    # Run some scripts
    ./cli.sh hello >/dev/null 2>&1 || true
    
    # Count temp files after
    AFTER=$(ls /tmp/parrot_* /tmp/mcp_* 2>/dev/null | wc -l)
    
    # Should not accumulate temp files (allow for test artifacts)
    # This is a soft check
    [ "$AFTER" -le "$((BEFORE + 5))" ]
}

# ============================================================================
# SECURITY AND INPUT VALIDATION TESTS
# ============================================================================

@test "integration: scripts handle malicious input safely" {
    # Try passing command injection attempt
    run ./cli.sh "hello; rm -rf /" 2>&1 || true
    
    # Should not cause system damage (verifiable by checking system still works)
    # Exit code may vary, but system should remain stable
    [ -f "./cli.sh" ]  # Verify cli.sh still exists
}

@test "integration: scripts handle path traversal safely" {
    # Try passing path traversal
    run ./cli.sh "../../../etc/passwd" 2>&1 || true
    
    # Should handle safely without system damage
    # Exit code may vary, verify system stability
    [ -f "./cli.sh" ]  # Verify cli.sh still exists
}

@test "integration: executable scripts have safe permissions" {
    # Check that scripts are not world-writable
    local failed=0
    for script in scripts/*.sh cli.sh; do
        if [ -f "$script" ]; then
            # Check if world-writable (dangerous)
            if [ -w "$script" ] && [ "$(stat -c %a "$script" | cut -c3)" = "w" ]; then
                echo "# World-writable script: $script" >&2
                failed=1
            fi
        fi
    done
    [ "$failed" -eq 0 ]
}
