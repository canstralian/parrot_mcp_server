#!/usr/bin/env bats
# Security Tools Tests
# Tests for security tools integration

# Setup function - runs before each test
setup() {
    # Load common configuration
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
    source "${SCRIPT_DIR}/common_config.sh"

    # Load security configuration
    source "${SCRIPT_DIR}/security-tools/security_config.sh"

    # Test directories
    TEST_RESULTS_DIR="${SECURITY_RESULTS_DIR}/test"
    mkdir -p "$TEST_RESULTS_DIR"
}

# Teardown function - runs after each test
teardown() {
    # Clean up test results
    rm -rf "$TEST_RESULTS_DIR" 2>/dev/null || true
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

@test "security_config.sh loads successfully" {
    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "security directories are created" {
    [ -d "$SECURITY_RESULTS_DIR" ]
    [ -d "$SECURITY_CONFIGS_DIR" ]
}

@test "security audit log is created" {
    [ -f "$SECURITY_AUDIT_LOG" ]
}

@test "IP whitelist file exists" {
    [ -f "$SECURITY_IP_WHITELIST_FILE" ]
}

@test "IP blacklist file exists" {
    [ -f "$SECURITY_IP_BLACKLIST_FILE" ]
}

@test "API key file is created" {
    [ -f "$SECURITY_API_KEY_FILE" ]
}

# =============================================================================
# AUDIT LOGGING TESTS
# =============================================================================

@test "security_audit function logs INFO level" {
    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_audit 'INFO' 'Test message'"
    [ "$status" -eq 0 ]

    # Check log file contains message
    run grep "Test message" "$SECURITY_AUDIT_LOG"
    [ "$status" -eq 0 ]
}

@test "security_audit function logs ERROR level" {
    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_audit 'ERROR' 'Test error'"
    [ "$status" -eq 0 ]

    # Check log file contains error
    run grep "ERROR.*Test error" "$SECURITY_AUDIT_LOG"
    [ "$status" -eq 0 ]
}

# =============================================================================
# USER AUTHORIZATION TESTS
# =============================================================================

@test "security_check_user allows authorized user" {
    # Set authorized users
    export SECURITY_AUTHORIZED_USERS="root,admin,testuser"

    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_check_user 'admin'"
    [ "$status" -eq 0 ]
}

@test "security_check_user rejects unauthorized user" {
    export SECURITY_AUTHORIZED_USERS="root,admin"

    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_check_user 'hacker'"
    [ "$status" -eq 1 ]
}

# =============================================================================
# TARGET VALIDATION TESTS (requires ipcalc)
# =============================================================================

@test "security_validate_target with localhost (whitelisted)" {
    # Skip if ipcalc not available
    if ! command -v ipcalc >/dev/null 2>&1; then
        skip "ipcalc not installed"
    fi

    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_validate_target '127.0.0.1'"
    [ "$status" -eq 0 ]
}

@test "security_validate_target rejects public DNS (blacklisted)" {
    if ! command -v ipcalc >/dev/null 2>&1; then
        skip "ipcalc not installed"
    fi

    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_validate_target '8.8.8.8'"
    [ "$status" -eq 1 ]
}

# =============================================================================
# RATE LIMITING TESTS
# =============================================================================

@test "security_check_rate_limit allows first request" {
    # Clean rate limit DB
    rm -f "$SECURITY_RATE_LIMIT_DB"
    touch "$SECURITY_RATE_LIMIT_DB"

    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 security_check_rate_limit 'testuser' 'test_scan'"
    [ "$status" -eq 0 ]
}

@test "security_check_rate_limit tracks requests" {
    rm -f "$SECURITY_RATE_LIMIT_DB"
    touch "$SECURITY_RATE_LIMIT_DB"

    bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
             security_check_rate_limit 'testuser' 'test_scan'"

    # Check that request was recorded
    [ -s "$SECURITY_RATE_LIMIT_DB" ]
    run grep "testuser:test_scan" "$SECURITY_RATE_LIMIT_DB"
    [ "$status" -eq 0 ]
}

# =============================================================================
# NMAP WRAPPER TESTS
# =============================================================================

@test "nmap_wrapper.sh exists and is executable" {
    [ -x "${SCRIPT_DIR}/security-tools/nmap_wrapper.sh" ]
}

@test "nmap_wrapper.sh shows help" {
    run "${SCRIPT_DIR}/security-tools/nmap_wrapper.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "nmap_wrapper.sh rejects missing target" {
    run "${SCRIPT_DIR}/security-tools/nmap_wrapper.sh" -u testuser -k testkey
    [ "$status" -eq 1 ]
    [[ "$output" == *"Target is required"* ]]
}

@test "nmap_wrapper.sh validates scan type" {
    # This will fail auth/rate limiting, but should validate scan type first
    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 nmap_validate_scan_type 'tcp'"
    [ "$status" -eq 0 ]
    [[ "$output" == "-sS" ]]
}

@test "nmap_wrapper.sh rejects invalid scan type" {
    run bash -c "source '${SCRIPT_DIR}/security-tools/security_config.sh' && \
                 source '${SCRIPT_DIR}/security-tools/nmap_wrapper.sh' && \
                 nmap_validate_scan_type 'invalid'"
    [ "$status" -eq 1 ]
}

# =============================================================================
# OPENVAS WRAPPER TESTS
# =============================================================================

@test "openvas_wrapper.sh exists and is executable" {
    [ -x "${SCRIPT_DIR}/security-tools/openvas_wrapper.sh" ]
}

@test "openvas_wrapper.sh shows help" {
    run "${SCRIPT_DIR}/security-tools/openvas_wrapper.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "openvas_wrapper.sh rejects missing target" {
    run "${SCRIPT_DIR}/security-tools/openvas_wrapper.sh" -u testuser -k testkey
    [ "$status" -eq 1 ]
    [[ "$output" == *"Target is required"* ]]
}

@test "openvas_wrapper.sh validates config UUID" {
    run bash -c "source '${SCRIPT_DIR}/security-tools/openvas_wrapper.sh' && \
                 openvas_get_config_uuid 'full_and_fast'"
    # Will output UUID (even without OpenVAS installed)
    [[ "$output" == "daba56c8-73ec-11df-9d8c-002264764cea" ]]
}

# =============================================================================
# SECURITY API TESTS
# =============================================================================

@test "security_api.py exists and is executable" {
    [ -x "${SCRIPT_DIR}/security-tools/security_api.py" ]
}

@test "security_api.py has valid Python syntax" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi

    run python3 -m py_compile "${SCRIPT_DIR}/security-tools/security_api.py"
    [ "$status" -eq 0 ]
}

@test "requirements.txt exists" {
    [ -f "${SCRIPT_DIR}/security-tools/requirements.txt" ]
}

# =============================================================================
# DOCUMENTATION TESTS
# =============================================================================

@test "LEGAL_NOTICE.txt exists" {
    [ -f "${SCRIPT_DIR}/security-tools/LEGAL_NOTICE.txt" ]
}

@test "LEGAL_NOTICE.txt contains warning" {
    run grep "AUTHORIZED USE ONLY" "${SCRIPT_DIR}/security-tools/LEGAL_NOTICE.txt"
    [ "$status" -eq 0 ]
}

@test "SECURITY_TOOLS.md documentation exists" {
    [ -f "${SCRIPT_DIR}/../docs/SECURITY_TOOLS.md" ]
}

# =============================================================================
# FILE PERMISSIONS TESTS
# =============================================================================

@test "security results directory has restrictive permissions" {
    # Check that directory is mode 700 (owner only)
    perms=$(stat -c "%a" "$SECURITY_RESULTS_DIR")
    [ "$perms" = "700" ]
}

@test "security configs directory has restrictive permissions" {
    perms=$(stat -c "%a" "$SECURITY_CONFIGS_DIR")
    [ "$perms" = "700" ]
}

@test "API key file has restrictive permissions" {
    perms=$(stat -c "%a" "$SECURITY_API_KEY_FILE")
    [ "$perms" = "600" ]
}

@test "audit log has restrictive permissions" {
    perms=$(stat -c "%a" "$SECURITY_AUDIT_LOG")
    [ "$perms" = "600" ]
}
