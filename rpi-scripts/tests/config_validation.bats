#!/usr/bin/env bats
# config_validation.bats - Tests for common_config.sh validation and security functions

# Load common configuration
setup() {
    load '../common_config.sh'
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
}

teardown() {
    # Cleanup temporary test directory
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# ============================================================================
# EMAIL VALIDATION TESTS
# ============================================================================

@test "parrot_validate_email: accepts valid email address" {
    run parrot_validate_email "user@example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: accepts email with subdomain" {
    run parrot_validate_email "admin@mail.example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: accepts email with plus addressing" {
    run parrot_validate_email "user+tag@example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: accepts email with dots" {
    run parrot_validate_email "first.last@example.co.uk"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: rejects email without @" {
    run parrot_validate_email "userexample.com"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_email: rejects email without domain" {
    run parrot_validate_email "user@"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_email: rejects email without TLD" {
    run parrot_validate_email "user@example"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_email: rejects email with spaces" {
    run parrot_validate_email "user name@example.com"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_email: rejects email with special characters" {
    run parrot_validate_email "user;rm -rf /@example.com"
    [ "$status" -eq 1 ]
}

# ============================================================================
# NUMBER VALIDATION TESTS
# ============================================================================

@test "parrot_validate_number: accepts positive integer" {
    run parrot_validate_number "42"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_number: accepts zero" {
    run parrot_validate_number "0"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_number: accepts large number" {
    run parrot_validate_number "999999999"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_number: rejects negative number" {
    run parrot_validate_number "-5"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_number: rejects decimal number" {
    run parrot_validate_number "3.14"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_number: rejects non-numeric input" {
    run parrot_validate_number "abc"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_number: rejects number with spaces" {
    run parrot_validate_number "1 2 3"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_number: rejects command injection attempt" {
    run parrot_validate_number "5; rm -rf /"
    [ "$status" -eq 1 ]
}

# ============================================================================
# PERCENTAGE VALIDATION TESTS
# ============================================================================

@test "parrot_validate_percentage: accepts 0" {
    run parrot_validate_percentage "0"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_percentage: accepts 50" {
    run parrot_validate_percentage "50"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_percentage: accepts 100" {
    run parrot_validate_percentage "100"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_percentage: rejects 101" {
    run parrot_validate_percentage "101"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_percentage: rejects negative" {
    run parrot_validate_percentage "-1"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_percentage: rejects non-numeric" {
    run parrot_validate_percentage "fifty"
    [ "$status" -eq 1 ]
}

# ============================================================================
# PATH VALIDATION TESTS
# ============================================================================

@test "parrot_validate_path: accepts absolute path" {
    run parrot_validate_path "/usr/local/bin/script.sh"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_path: accepts relative path" {
    run parrot_validate_path "logs/parrot.log"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_path: accepts current directory" {
    run parrot_validate_path "./script.sh"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_path: rejects path traversal with .." {
    run parrot_validate_path "../../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_path: rejects path with .. in middle" {
    run parrot_validate_path "/usr/../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_path: rejects path with null byte" {
    # shellcheck disable=SC2028
    run parrot_validate_path "/tmp/test$(echo -e '\0')file"
    [ "$status" -eq 1 ]
}

# ============================================================================
# SCRIPT NAME VALIDATION TESTS
# ============================================================================

@test "parrot_validate_script_name: accepts simple name" {
    run parrot_validate_script_name "hello"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: accepts name with underscore" {
    run parrot_validate_script_name "check_disk"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: accepts name with hyphen" {
    run parrot_validate_script_name "health-check"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: accepts name with numbers" {
    run parrot_validate_script_name "script123"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: rejects name starting with number" {
    run parrot_validate_script_name "123script"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_script_name: rejects name with slash" {
    run parrot_validate_script_name "../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_script_name: rejects name with special characters" {
    run parrot_validate_script_name "script;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_script_name: rejects name with spaces" {
    run parrot_validate_script_name "my script"
    [ "$status" -eq 1 ]
}

# ============================================================================
# INPUT SANITIZATION TESTS
# ============================================================================

@test "parrot_sanitize_input: preserves clean input" {
    result=$(parrot_sanitize_input "Hello World")
    [ "$result" = "Hello World" ]
}

@test "parrot_sanitize_input: removes null bytes" {
    # shellcheck disable=SC2028
    result=$(parrot_sanitize_input "$(echo -e 'Hello\0World')")
    [ "$result" = "HelloWorld" ]
}

@test "parrot_sanitize_input: removes carriage returns" {
    # shellcheck disable=SC2028
    result=$(parrot_sanitize_input "$(echo -e 'Hello\rWorld')")
    [ "$result" = "HelloWorld" ]
}

@test "parrot_sanitize_input: preserves newlines" {
    # shellcheck disable=SC2028
    result=$(parrot_sanitize_input "$(echo -e 'Hello\nWorld')")
    [ "$result" = "$(echo -e 'Hello\nWorld')" ]
}

# ============================================================================
# SYSTEM UTILITY TESTS
# ============================================================================

@test "parrot_command_exists: finds existing command" {
    run parrot_command_exists "bash"
    [ "$status" -eq 0 ]
}

@test "parrot_command_exists: fails for non-existent command" {
    run parrot_command_exists "nonexistentcommand123456"
    [ "$status" -eq 1 ]
}

@test "parrot_is_root: detects non-root user" {
    if [ "$(id -u)" -ne 0 ]; then
        run parrot_is_root
        [ "$status" -eq 1 ]
    else
        skip "Running as root, cannot test non-root detection"
    fi
}

# ============================================================================
# SECURE TEMP FILE TESTS
# ============================================================================

@test "parrot_mktemp: creates temporary file" {
    tmpfile=$(parrot_mktemp)
    [ -f "$tmpfile" ]
    rm -f "$tmpfile"
}

@test "parrot_mktemp: sets secure permissions (600)" {
    tmpfile=$(parrot_mktemp)
    perms=$(stat -c "%a" "$tmpfile" 2>/dev/null || stat -f "%A" "$tmpfile" 2>/dev/null)
    [ "$perms" = "600" ]
    rm -f "$tmpfile"
}

@test "parrot_mktemp: creates unique files" {
    tmpfile1=$(parrot_mktemp)
    tmpfile2=$(parrot_mktemp)
    [ "$tmpfile1" != "$tmpfile2" ]
    rm -f "$tmpfile1" "$tmpfile2"
}

# ============================================================================
# JSON VALIDATION TESTS
# ============================================================================

@test "parrot_validate_json: accepts valid JSON file" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not installed"
    fi

    echo '{"method": "ping", "params": {}}' > "$TEST_DIR/valid.json"
    run parrot_validate_json "$TEST_DIR/valid.json"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_json: rejects invalid JSON file" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not installed"
    fi

    echo '{"method": "ping", invalid json}' > "$TEST_DIR/invalid.json"
    run parrot_validate_json "$TEST_DIR/invalid.json"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_json: rejects non-existent file" {
    run parrot_validate_json "$TEST_DIR/nonexistent.json"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_json: rejects file exceeding max size" {
    # Create file larger than default max size (1MB)
    dd if=/dev/zero of="$TEST_DIR/large.json" bs=1M count=2 2>/dev/null
    run parrot_validate_json "$TEST_DIR/large.json"
    [ "$status" -eq 1 ]
}

# ============================================================================
# LOGGING TESTS
# ============================================================================

@test "parrot_log: creates log entry" {
    export PARROT_LOG_DIR="$TEST_DIR"
    export PARROT_SERVER_LOG="$TEST_DIR/test.log"
    parrot_log "INFO" "Test message"
    [ -f "$TEST_DIR/test.log" ]
    grep -q "Test message" "$TEST_DIR/test.log"
}

@test "parrot_log: includes timestamp" {
    export PARROT_LOG_DIR="$TEST_DIR"
    export PARROT_SERVER_LOG="$TEST_DIR/test.log"
    parrot_log "INFO" "Test message"
    grep -q '\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$TEST_DIR/test.log"
}

@test "parrot_log: includes message ID" {
    export PARROT_LOG_DIR="$TEST_DIR"
    export PARROT_SERVER_LOG="$TEST_DIR/test.log"
    parrot_log "INFO" "Test message"
    grep -q '\[msgid:[0-9]\+\]' "$TEST_DIR/test.log"
}

@test "parrot_log: includes log level" {
    export PARROT_LOG_DIR="$TEST_DIR"
    export PARROT_SERVER_LOG="$TEST_DIR/test.log"
    parrot_log "ERROR" "Test error"
    grep -q '\[ERROR\]' "$TEST_DIR/test.log"
}

# ============================================================================
# SECURITY INJECTION TESTS
# ============================================================================

@test "SECURITY: email validation blocks command injection" {
    run parrot_validate_email "user@example.com; rm -rf /"
    [ "$status" -eq 1 ]
}

@test "SECURITY: path validation blocks directory traversal" {
    run parrot_validate_path "../../../../etc/shadow"
    [ "$status" -eq 1 ]
}

@test "SECURITY: script name validation blocks path injection" {
    run parrot_validate_script_name "../../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "SECURITY: number validation blocks command injection" {
    run parrot_validate_number "42; cat /etc/passwd"
    [ "$status" -eq 1 ]
}

@test "SECURITY: percentage validation prevents overflow" {
    run parrot_validate_percentage "9999999999999"
    [ "$status" -eq 1 ]
}
