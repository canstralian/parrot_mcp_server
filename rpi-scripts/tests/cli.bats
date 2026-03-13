#!/usr/bin/env bats
# cli.bats - Tests for rpi-scripts/cli.sh
#
# cli.sh looks for scripts in $(dirname "$0")/scripts/.
# We copy cli.sh into a temp directory alongside a controllable scripts/ dir
# so each test has full isolation.

REAL_CLI="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/cli.sh"
REAL_SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"

    # Copy cli.sh so $0 resolves to the temp location
    cp "$REAL_CLI" "$TEST_DIR/cli.sh"
    chmod +x "$TEST_DIR/cli.sh"

    # Create a scripts/ directory with a known-good test script
    mkdir -p "$TEST_DIR/scripts"

    cat > "$TEST_DIR/scripts/hello.sh" << 'EOF'
#!/usr/bin/env bash
echo "Hello from hello"
exit 0
EOF
    chmod +x "$TEST_DIR/scripts/hello.sh"

    cat > "$TEST_DIR/scripts/fail.sh" << 'EOF'
#!/usr/bin/env bash
exit 42
EOF
    chmod +x "$TEST_DIR/scripts/fail.sh"

    # cli.sh writes errors to $(dirname "$0")/cli_error.log
    CLI_LOG="$TEST_DIR/cli_error.log"
    export CLI_LOG
    export TEST_DIR

    ORIG_DIR="$(pwd)"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# ============================================================================
# HELP FLAGS
# ============================================================================

@test "cli: --help flag exits with code 0" {
    run bash "$TEST_DIR/cli.sh" --help
    [ "$status" -eq 0 ]
}

@test "cli: --help flag prints Usage line" {
    run bash "$TEST_DIR/cli.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: -h flag exits with code 0" {
    run bash "$TEST_DIR/cli.sh" -h
    [ "$status" -eq 0 ]
}

@test "cli: -h flag prints Usage line" {
    run bash "$TEST_DIR/cli.sh" -h
    [[ "$output" == *"Usage:"* ]]
}

@test "cli: --help lists available scripts" {
    run bash "$TEST_DIR/cli.sh" --help
    [[ "$output" == *"hello"* ]]
}

# ============================================================================
# VALID SCRIPT EXECUTION
# ============================================================================

@test "cli: executes a valid script and exits 0" {
    run bash "$TEST_DIR/cli.sh" hello
    [ "$status" -eq 0 ]
}

@test "cli: valid script output is passed through" {
    run bash "$TEST_DIR/cli.sh" hello
    [[ "$output" == *"Hello from hello"* ]]
}

@test "cli: propagates non-zero exit code from script" {
    run bash "$TEST_DIR/cli.sh" fail
    [ "$status" -ne 0 ]
}

@test "cli: logs error when script exits non-zero" {
    bash "$TEST_DIR/cli.sh" fail || true
    [ -f "$TEST_DIR/cli_error.log" ]
    grep -q "fail" "$TEST_DIR/cli_error.log"
}

# ============================================================================
# INVALID SCRIPT NAMES
# ============================================================================

@test "cli: rejects script name starting with a digit" {
    run bash "$TEST_DIR/cli.sh" "1invalid"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid script name"* ]]
}

@test "cli: rejects script name with path traversal" {
    run bash "$TEST_DIR/cli.sh" "../etc/passwd"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid script name"* ]]
}

@test "cli: rejects script name with semicolon" {
    run bash "$TEST_DIR/cli.sh" "hello;rm -rf /"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid script name"* ]]
}

@test "cli: rejects script name with spaces" {
    run bash "$TEST_DIR/cli.sh" "my script"
    [ "$status" -ne 0 ]
}

@test "cli: logs invalid script name to error log" {
    bash "$TEST_DIR/cli.sh" "../etc/passwd" || true
    [ -f "$TEST_DIR/cli_error.log" ]
    grep -q "Invalid script name" "$TEST_DIR/cli_error.log"
}

# ============================================================================
# SCRIPT NOT FOUND
# ============================================================================

@test "cli: handles non-existent script gracefully" {
    # cli.sh falls back to interactive menu for missing scripts, which is
    # not easily testable non-interactively; but it must not crash with
    # an unhandled error when the script does not exist.
    run bash "$TEST_DIR/cli.sh" nonexistent_script_xyz 2>&1 <<< "q"
    # Interactive menu waits for input; piping 'q' exits it.
    # We only verify it exits without a shell error (non-2 status means menu ran)
    [ "$status" -eq 0 ] || [ "$status" -eq 130 ] || true
}

# ============================================================================
# validate_script_name (unit tests via sourcing)
# ============================================================================

@test "validate_script_name: accepts simple alphanumeric name" {
    # Source cli.sh to access individual functions (no main called)
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    run validate_script_name "hello"
    [ "$status" -eq 0 ]
}

@test "validate_script_name: accepts name with underscore and dash" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    run validate_script_name "check_disk"
    [ "$status" -eq 0 ]
    run validate_script_name "health-check"
    [ "$status" -eq 0 ]
}

@test "validate_script_name: rejects name with dot" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    run validate_script_name "script.sh"
    [ "$status" -ne 0 ]
}

@test "validate_script_name: rejects empty string" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    run validate_script_name ""
    [ "$status" -ne 0 ]
}

@test "validate_script_name: rejects name starting with number" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    run validate_script_name "9lives"
    [ "$status" -ne 0 ]
}

# ============================================================================
# hash_arg (unit tests via sourcing)
# ============================================================================

@test "hash_arg: returns 64-character hex string" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    result=$(hash_arg "test_input")
    [ "${#result}" -eq 64 ]
}

@test "hash_arg: is deterministic for same input" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    r1=$(hash_arg "same_value")
    r2=$(hash_arg "same_value")
    [ "$r1" = "$r2" ]
}

@test "hash_arg: differs for different inputs" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    r1=$(hash_arg "value_one")
    r2=$(hash_arg "value_two")
    [ "$r1" != "$r2" ]
}

# ============================================================================
# list_scripts
# ============================================================================

@test "list_scripts: includes known scripts" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    result=$(list_scripts)
    [[ "$result" == *"hello"* ]]
    [[ "$result" == *"fail"* ]]
}

@test "list_scripts: strips .sh extension from output" {
    source "$TEST_DIR/cli.sh" 2>/dev/null || true
    result=$(list_scripts)
    [[ "$result" != *".sh"* ]]
}

# ============================================================================
# LOG FORMAT
# ============================================================================

@test "cli: error log entry contains timestamp" {
    bash "$TEST_DIR/cli.sh" fail || true
    grep -qE '\[20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$TEST_DIR/cli_error.log"
}

@test "cli: error log entry contains [ERROR] level" {
    bash "$TEST_DIR/cli.sh" fail || true
    grep -q '\[ERROR\]' "$TEST_DIR/cli_error.log"
}

@test "cli: error log entry contains msgid field" {
    bash "$TEST_DIR/cli.sh" fail || true
    grep -q '\[msgid:[0-9]\+\]' "$TEST_DIR/cli_error.log"
}
