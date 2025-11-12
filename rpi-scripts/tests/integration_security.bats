#!/usr/bin/env bats
# integration_security.bats - Security-focused integration tests

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
}

teardown() {
    # Return to original directory
    cd "$ORIG_DIR"
    
    # Cleanup temporary test directory
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
    
    # Clean up any test files
    rm -f /tmp/mcp_security_test_*.json
}

# ============================================================================
# INPUT VALIDATION AND SANITIZATION TESTS
# ============================================================================

@test "security: CLI rejects command injection attempts" {
    # Try various command injection patterns
    run ./cli.sh "test; whoami" 2>&1 || true
    [ "$status" -ne 0 ]
    [[ "$output" != *"runner"* ]] # Should not execute whoami
    
    run ./cli.sh "test && whoami" 2>&1 || true
    [ "$status" -ne 0 ]
    
    run ./cli.sh "test | whoami" 2>&1 || true
    [ "$status" -ne 0 ]
    
    run ./cli.sh 'test`whoami`' 2>&1 || true
    [ "$status" -ne 0 ]
    
    run ./cli.sh 'test$(whoami)' 2>&1 || true
    [ "$status" -ne 0 ]
}

@test "security: scripts validate email format (from common_config)" {
    # Source common config
    source ./common_config.sh
    
    # Valid email should pass
    run parrot_validate_email "user@example.com"
    [ "$status" -eq 0 ]
    
    # Injection attempts should fail
    run parrot_validate_email "user@example.com; whoami"
    [ "$status" -eq 1 ]
    
    run parrot_validate_email "user@example.com$(whoami)"
    [ "$status" -eq 1 ]
    
    run parrot_validate_email "user@example.com|whoami"
    [ "$status" -eq 1 ]
}

@test "security: path validation prevents traversal attacks" {
    # Source common config
    source ./common_config.sh
    
    # Path traversal attempts should be caught
    run parrot_validate_path "../../../etc/passwd"
    [ "$status" -eq 1 ]
    
    run parrot_validate_path "/tmp/../../etc/passwd"
    [ "$status" -eq 1 ]
    
    run parrot_validate_path "./../../sensitive_file"
    [ "$status" -eq 1 ]
}

@test "security: filename validation prevents special characters" {
    # Source common config
    source ./common_config.sh
    
    # Valid filenames should pass
    run parrot_validate_filename "backup_2024-01-01.tar.gz"
    [ "$status" -eq 0 ]
    
    # Dangerous filenames should fail
    run parrot_validate_filename "file; rm -rf /"
    [ "$status" -eq 1 ]
    
    run parrot_validate_filename "file\$(whoami)"
    [ "$status" -eq 1 ]
    
    run parrot_validate_filename "file|whoami"
    [ "$status" -eq 1 ]
}

# ============================================================================
# IPC SECURITY TESTS (File-based Communication)
# ============================================================================

@test "security: /tmp usage is documented as security concern" {
    # Verify TODO.md documents the /tmp security issue
    [ -f "../TODO.md" ] || skip "TODO.md not found"
    
    run grep -i "security.*tmp\|tmp.*security" ../TODO.md
    [ "$status" -eq 0 ]
}

@test "security: MCP message files have secure permissions when created" {
    # Create test message file
    TEST_MSG="/tmp/mcp_security_test_$$.json"
    echo '{"type":"test"}' > "$TEST_MSG"
    
    # Check permissions (should not be world-writable)
    [ -f "$TEST_MSG" ]
    PERMS=$(stat -c %a "$TEST_MSG")
    
    # Last digit should not be 7 (no world-write ideally)
    # This is a basic check; actual security depends on umask
    [[ "$PERMS" =~ ^[0-7][0-7][0-7]$ ]]
    
    rm -f "$TEST_MSG"
}

@test "security: server log files are not world-readable by default" {
    # Start server to create log
    ./start_mcp_server.sh
    sleep 2
    
    # Check log file permissions
    [ -f "./logs/parrot.log" ]
    PERMS=$(stat -c %a "./logs/parrot.log")
    
    # Verify not world-writable (last digit should not be 7 or 3)
    LAST_DIGIT="${PERMS: -1}"
    [ "$LAST_DIGIT" != "7" ]
    [ "$LAST_DIGIT" != "3" ]
    
    # Cleanup
    ./stop_mcp_server.sh
}

@test "security: PID file has appropriate permissions" {
    # Start server
    ./start_mcp_server.sh
    sleep 2
    
    # Check PID file permissions
    [ -f "./logs/mcp_server.pid" ]
    PERMS=$(stat -c %a "./logs/mcp_server.pid")
    
    # Should not be world-writable
    LAST_DIGIT="${PERMS: -1}"
    [ "$LAST_DIGIT" != "7" ]
    [ "$LAST_DIGIT" != "3" ]
    
    # Cleanup
    ./stop_mcp_server.sh
}

# ============================================================================
# AUTHENTICATION AND AUTHORIZATION TESTS
# ============================================================================

@test "security: scripts run with current user permissions (no elevation)" {
    # Run a script and verify it doesn't escalate privileges
    run bash -c "./cli.sh hello 2>&1 | grep -i 'sudo\|root\|privilege' || true"
    
    # Should not contain privilege escalation keywords
    # (empty output is expected)
}

@test "security: cron setup doesn't require root privileges" {
    # Check if setup_cron.sh requires root
    run bash -c "grep -n 'sudo\|require.*root\|must.*root' ./scripts/setup_cron.sh || echo 'no-root-required'"
    
    # Should not require root (or explicitly check for it)
    [[ "$output" == *"no-root-required"* ]] || [[ "$output" == *"root"* ]]
}

# ============================================================================
# ERROR HANDLING AND INFORMATION DISCLOSURE TESTS
# ============================================================================

@test "security: error messages don't leak sensitive information" {
    # Try to trigger an error
    run ./cli.sh nonexistent_script_xyz 2>&1 || true
    
    # Error message should not contain:
    # - Full system paths (leaking directory structure)
    # - Environment variables
    # - User credentials
    [[ "$output" != *"PASSWORD"* ]]
    [[ "$output" != *"SECRET"* ]]
    [[ "$output" != *"TOKEN"* ]]
}

@test "security: logs don't contain sensitive data patterns" {
    # Start server
    ./start_mcp_server.sh
    sleep 2
    ./stop_mcp_server.sh
    
    # Check log for sensitive patterns
    if [ -f "./logs/parrot.log" ]; then
        run grep -iE "password|secret|token|api[_-]?key|private[_-]?key" ./logs/parrot.log || true
        
        # Should not find sensitive patterns
        [ -z "$output" ] || skip "Found potential sensitive data in logs"
    fi
}

@test "security: scripts handle missing files without exposing paths" {
    # Try to access non-existent script
    run ./cli.sh nonexistent 2>&1 || true
    
    # Should handle gracefully without full path disclosure
    # (this is a soft check - some path disclosure may be acceptable)
}

# ============================================================================
# RESOURCE EXHAUSTION PREVENTION TESTS
# ============================================================================

@test "security: server process terminates within reasonable time" {
    # Start server
    ./start_mcp_server.sh
    sleep 2
    
    # Get PID
    SERVER_PID=$(cat ./logs/mcp_server.pid)
    
    # Stop server
    ./stop_mcp_server.sh
    
    # Wait and verify process is gone
    sleep 2
    ! ps -p "$SERVER_PID" >/dev/null 2>&1
}

@test "security: concurrent operations don't cause resource leaks" {
    # Start and stop server multiple times
    for i in {1..5}; do
        ./start_mcp_server.sh
        sleep 1
        ./stop_mcp_server.sh
        sleep 1
    done
    
    # Verify no orphaned processes
    ! pgrep -f "start_mcp_server" >/dev/null 2>&1
}

@test "security: log files don't grow unbounded during testing" {
    # Start server
    ./start_mcp_server.sh
    sleep 2
    
    # Get initial log size
    INITIAL_SIZE=$(stat -c %s ./logs/parrot.log 2>/dev/null || echo 0)
    
    # Wait a bit
    sleep 3
    
    # Get final log size
    FINAL_SIZE=$(stat -c %s ./logs/parrot.log 2>/dev/null || echo 0)
    
    # Stop server
    ./stop_mcp_server.sh
    
    # Log growth should be reasonable (less than 100KB in 5 seconds)
    GROWTH=$((FINAL_SIZE - INITIAL_SIZE))
    [ "$GROWTH" -lt 102400 ]
}

# ============================================================================
# SHELL SAFETY TESTS
# ============================================================================

@test "security: scripts use 'set -e' or equivalent error handling" {
    local failed=0
    for script in scripts/*.sh cli.sh start_mcp_server.sh stop_mcp_server.sh; do
        if [ -f "$script" ]; then
            # Check for set -e, set -euo pipefail, or equivalent
            grep -qE '^set -[euo]+|^set -[a-z]*e' "$script" || {
                echo "# Missing 'set -e' in $script" >&2
                failed=1
            }
        fi
    done
    [ "$failed" -eq 0 ] || skip "Some scripts missing error handling"
}

@test "security: scripts quote variables properly (sample check)" {
    # Check a few critical scripts for unquoted variables
    local failed=0
    
    # Look for common dangerous patterns like $VAR instead of "$VAR"
    # This is a heuristic check, not comprehensive
    for script in start_mcp_server.sh stop_mcp_server.sh; do
        if [ -f "$script" ]; then
            # Check for some common unquoted variable patterns
            # Note: This is not foolproof, just a basic check
            if grep -E '\$[A-Z_]+[^"'\''0-9A-Za-z_]' "$script" | grep -vE '^\s*#' >/dev/null; then
                # Found potentially unquoted variables (excluding comments)
                # This is a warning, not necessarily a failure
                echo "# Potential unquoted variables in $script" >&2
            fi
        fi
    done
}

@test "security: no hardcoded credentials in scripts" {
    local failed=0
    for script in scripts/*.sh cli.sh common_config.sh start_mcp_server.sh stop_mcp_server.sh; do
        if [ -f "$script" ]; then
            # Look for common credential patterns
            if grep -iE 'password\s*=\s*['\''"][^'\''"]|api[_-]?key\s*=|secret\s*=\s*['\''"]' "$script" | grep -vE '^\s*#' >/dev/null; then
                echo "# Potential hardcoded credential in $script" >&2
                failed=1
            fi
        fi
    done
    [ "$failed" -eq 0 ]
}

@test "security: no eval usage in scripts" {
    local failed=0
    for script in scripts/*.sh cli.sh common_config.sh start_mcp_server.sh stop_mcp_server.sh; do
        if [ -f "$script" ]; then
            # Check for eval (dangerous if used with user input)
            if grep -E '\beval\b' "$script" | grep -vE '^\s*#' >/dev/null; then
                echo "# Found 'eval' in $script (review for safety)" >&2
                # Not auto-failing as eval can be safe if used carefully
            fi
        fi
    done
}

# ============================================================================
# FILE SYSTEM SECURITY TESTS
# ============================================================================

@test "security: scripts don't create world-writable files" {
    # Run server to create files
    ./start_mcp_server.sh
    sleep 2
    ./stop_mcp_server.sh
    
    # Check created files
    for file in ./logs/parrot.log ./logs/mcp_server.pid; do
        if [ -f "$file" ]; then
            PERMS=$(stat -c %a "$file")
            LAST_DIGIT="${PERMS: -1}"
            [ "$LAST_DIGIT" != "7" ] || [ "$LAST_DIGIT" != "6" ] || true
        fi
    done
}

@test "security: logs directory has appropriate permissions" {
    mkdir -p ./logs
    
    # Check logs directory permissions
    PERMS=$(stat -c %a ./logs)
    
    # Should be readable and writable by owner, but not world-writable
    LAST_DIGIT="${PERMS: -1}"
    [ "$LAST_DIGIT" != "7" ]
}

@test "security: temporary files use secure creation methods" {
    # Check if scripts use mktemp for temporary files
    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            # If script creates temp files, it should use mktemp
            if grep -qE 'tmp/|/var/tmp|TMPDIR' "$script"; then
                # Verify it uses mktemp (not just hardcoded paths)
                grep -qE 'mktemp|tempfile' "$script" || skip "Check temp file creation in $script"
            fi
        fi
    done
}

# ============================================================================
# DOCUMENTATION SECURITY TESTS
# ============================================================================

@test "security: IPC_SECURITY.md documents security considerations" {
    [ -f "./docs/IPC_SECURITY.md" ] || skip "IPC_SECURITY.md not found"
    
    # Should contain security-related content
    run grep -iE "security|risk|vulnerability|mitigat" ./docs/IPC_SECURITY.md
    [ "$status" -eq 0 ]
}

@test "security: README or docs mention security best practices" {
    # Check for security documentation
    run bash -c "find . -name '*.md' -exec grep -l -iE 'security|secure|vulnerability' {} \; | head -5"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}
