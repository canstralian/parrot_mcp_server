#!/usr/bin/env bats
# common_config_extended.bats
# Tests for previously untested common_config.sh functions:
#   - parrot_send_notification
#   - parrot_retry
#   - parrot_check_perms

setup() {
    load '../common_config.sh'

    TEST_DIR="$(mktemp -d)"
    BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$BIN_DIR"

    # Prepend our fake-command directory to PATH
    export ORIG_PATH="$PATH"
    export PATH="$BIN_DIR:$PATH"

    # Point logs to the test directory
    export PARROT_LOG_DIR="$TEST_DIR/logs"
    export PARROT_SERVER_LOG="$TEST_DIR/logs/parrot.log"
    mkdir -p "$PARROT_LOG_DIR"

    # Default: no email recipient, non-dry-run, strict perms
    export PARROT_ALERT_EMAIL=""
    export PARROT_DRY_RUN="false"
    export PARROT_STRICT_PERMS="true"

    # Fast retries for testing (override exponential backoff)
    export PARROT_RETRY_COUNT=3
    export PARROT_RETRY_DELAY=0
}

teardown() {
    export PATH="$ORIG_PATH"
    rm -rf "$TEST_DIR"
}

# Helper: create a fake command in BIN_DIR
_fake_cmd() {
    local name="$1"
    local body="${2:-exit 0}"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$BIN_DIR/$name"
    chmod +x "$BIN_DIR/$name"
}

# ============================================================================
# parrot_send_notification
# ============================================================================

@test "parrot_send_notification: returns 0 when no recipient is configured" {
    export PARROT_ALERT_EMAIL=""
    run parrot_send_notification "Subject" "Body"
    [ "$status" -eq 0 ]
}

@test "parrot_send_notification: returns 0 when recipient arg overrides empty PARROT_ALERT_EMAIL" {
    # mail command must exist for this to work; provide a no-op one
    _fake_cmd "mail" "exit 0"
    run parrot_send_notification "Subject" "Body" "ops@example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_send_notification: returns 1 for invalid email address" {
    run parrot_send_notification "Subject" "Body" "not-an-email"
    [ "$status" -eq 1 ]
}

@test "parrot_send_notification: returns 1 when mail command is absent" {
    # Ensure 'mail' is not on PATH
    run parrot_send_notification "Subject" "Body" "ops@example.com"
    [ "$status" -eq 1 ]
}

@test "parrot_send_notification: returns 0 in DRY_RUN mode (no mail command needed)" {
    export PARROT_DRY_RUN="true"
    run parrot_send_notification "Subject" "Body" "ops@example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_send_notification: DRY_RUN does not invoke mail" {
    export PARROT_DRY_RUN="true"
    MAIL_LOG="$TEST_DIR/mail_called"
    _fake_cmd "mail" "touch '$MAIL_LOG'; exit 0"

    parrot_send_notification "Subject" "Body" "ops@example.com"
    [ ! -f "$MAIL_LOG" ]
}

@test "parrot_send_notification: invokes mail with correct recipient" {
    _fake_cmd "mail" "echo \"ARGS: \$*\" > '$TEST_DIR/mail_args'; exit 0"
    parrot_send_notification "Test Subject" "Test Body" "team@example.com"
    grep -q "team@example.com" "$TEST_DIR/mail_args"
}

@test "parrot_send_notification: subject includes email prefix" {
    _fake_cmd "mail" "echo \"ARGS: \$*\" > '$TEST_DIR/mail_args'; exit 0"
    parrot_send_notification "Alert!" "Body text" "ops@example.com"
    grep -q "\[Parrot MCP\]" "$TEST_DIR/mail_args"
}

@test "parrot_send_notification: validates email from PARROT_ALERT_EMAIL" {
    export PARROT_ALERT_EMAIL="invalid@@bad"
    run parrot_send_notification "Subject" "Body"
    [ "$status" -eq 1 ]
}

# ============================================================================
# parrot_retry
# ============================================================================

@test "parrot_retry: returns 0 when command succeeds on first attempt" {
    run parrot_retry true
    [ "$status" -eq 0 ]
}

@test "parrot_retry: returns 1 when command always fails" {
    run parrot_retry 3 false
    [ "$status" -eq 1 ]
}

@test "parrot_retry: retries the correct number of times" {
    COUNTER_FILE="$TEST_DIR/counter"
    echo 0 > "$COUNTER_FILE"

    _increment_and_fail() {
        local c
        c=$(cat "$COUNTER_FILE")
        echo $((c + 1)) > "$COUNTER_FILE"
        return 1
    }
    export -f _increment_and_fail

    parrot_retry 3 bash -c '_increment_and_fail' 2>/dev/null || true
    final=$(cat "$COUNTER_FILE")
    [ "$final" -eq 3 ]
}

@test "parrot_retry: succeeds when command eventually passes" {
    COUNTER_FILE="$TEST_DIR/counter2"
    echo 0 > "$COUNTER_FILE"

    _fail_twice_then_pass() {
        local c
        c=$(cat "$COUNTER_FILE")
        echo $((c + 1)) > "$COUNTER_FILE"
        [ "$((c + 1))" -ge 3 ]
    }
    export -f _fail_twice_then_pass

    run parrot_retry 5 bash -c '_fail_twice_then_pass'
    [ "$status" -eq 0 ]
    [ "$(cat "$COUNTER_FILE")" -ge 3 ]
}

@test "parrot_retry: uses PARROT_RETRY_COUNT when no explicit count given" {
    export PARROT_RETRY_COUNT=2
    COUNTER_FILE="$TEST_DIR/counter3"
    echo 0 > "$COUNTER_FILE"

    _count_calls() {
        local c
        c=$(cat "$COUNTER_FILE")
        echo $((c + 1)) > "$COUNTER_FILE"
        return 1
    }
    export -f _count_calls

    parrot_retry bash -c '_count_calls' 2>/dev/null || true
    [ "$(cat "$COUNTER_FILE")" -eq 2 ]
}

@test "parrot_retry: explicit count overrides PARROT_RETRY_COUNT" {
    export PARROT_RETRY_COUNT=10  # Would run 10 times if not overridden
    COUNTER_FILE="$TEST_DIR/counter4"
    echo 0 > "$COUNTER_FILE"

    _always_fail_and_count() {
        local c
        c=$(cat "$COUNTER_FILE")
        echo $((c + 1)) > "$COUNTER_FILE"
        return 1
    }
    export -f _always_fail_and_count

    parrot_retry 2 bash -c '_always_fail_and_count' 2>/dev/null || true
    [ "$(cat "$COUNTER_FILE")" -eq 2 ]
}

# ============================================================================
# parrot_check_perms
# ============================================================================

@test "parrot_check_perms: returns 1 for non-existent file" {
    run parrot_check_perms "$TEST_DIR/does_not_exist" "600"
    [ "$status" -eq 1 ]
}

@test "parrot_check_perms: returns 0 when permissions match exactly" {
    tmpfile="$(mktemp -p "$TEST_DIR")"
    chmod 600 "$tmpfile"
    run parrot_check_perms "$tmpfile" "600"
    [ "$status" -eq 0 ]
    rm -f "$tmpfile"
}

@test "parrot_check_perms: returns 1 when permissions mismatch with STRICT_PERMS=true" {
    export PARROT_STRICT_PERMS="true"
    tmpfile="$(mktemp -p "$TEST_DIR")"
    chmod 644 "$tmpfile"
    run parrot_check_perms "$tmpfile" "600"
    [ "$status" -eq 1 ]
    rm -f "$tmpfile"
}

@test "parrot_check_perms: returns 0 when permissions mismatch with STRICT_PERMS=false" {
    export PARROT_STRICT_PERMS="false"
    tmpfile="$(mktemp -p "$TEST_DIR")"
    chmod 644 "$tmpfile"
    run parrot_check_perms "$tmpfile" "600"
    [ "$status" -eq 0 ]
    rm -f "$tmpfile"
}

@test "parrot_check_perms: works for directories" {
    testdir="$(mktemp -d -p "$TEST_DIR")"
    chmod 700 "$testdir"
    run parrot_check_perms "$testdir" "700"
    [ "$status" -eq 0 ]
    rm -rf "$testdir"
}

@test "parrot_check_perms: returns 0 for 755 permissions when correct" {
    tmpfile="$(mktemp -p "$TEST_DIR")"
    chmod 755 "$tmpfile"
    run parrot_check_perms "$tmpfile" "755"
    [ "$status" -eq 0 ]
    rm -f "$tmpfile"
}

@test "parrot_check_perms: distinguishes 600 from 644" {
    export PARROT_STRICT_PERMS="true"
    tmpfile="$(mktemp -p "$TEST_DIR")"
    chmod 644 "$tmpfile"
    run parrot_check_perms "$tmpfile" "600"
    [ "$status" -eq 1 ]
    rm -f "$tmpfile"
}

# ============================================================================
# Log level filtering (parrot_log)
# ============================================================================

@test "parrot_log: DEBUG messages suppressed at INFO level" {
    export PARROT_LOG_LEVEL="INFO"
    export PARROT_SERVER_LOG="$TEST_DIR/logs/level_test.log"
    parrot_log "DEBUG" "this should not appear"
    run grep -c "this should not appear" "$TEST_DIR/logs/level_test.log" 2>/dev/null
    [ "${output:-0}" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "parrot_log: INFO messages pass at INFO level" {
    export PARROT_LOG_LEVEL="INFO"
    export PARROT_SERVER_LOG="$TEST_DIR/logs/level_test2.log"
    parrot_log "INFO" "info message visible"
    grep -q "info message visible" "$TEST_DIR/logs/level_test2.log"
}

@test "parrot_log: WARN messages pass at WARN level" {
    export PARROT_LOG_LEVEL="WARN"
    export PARROT_SERVER_LOG="$TEST_DIR/logs/level_test3.log"
    parrot_log "WARN" "warn message visible"
    grep -q "warn message visible" "$TEST_DIR/logs/level_test3.log"
}

@test "parrot_log: INFO messages suppressed at WARN level" {
    export PARROT_LOG_LEVEL="WARN"
    export PARROT_SERVER_LOG="$TEST_DIR/logs/level_test4.log"
    parrot_log "INFO" "info should be hidden"
    run grep -c "info should be hidden" "$TEST_DIR/logs/level_test4.log" 2>/dev/null
    [ "${output:-0}" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "parrot_log: ERROR messages written to stderr" {
    export PARROT_SERVER_LOG="$TEST_DIR/logs/level_test5.log"
    run bash -c "source $(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/common_config.sh 2>/dev/null; \
                 PARROT_SERVER_LOG=$TEST_DIR/logs/level_test5.log; \
                 parrot_log ERROR 'stderr error message' 2>&1 >/dev/null"
    [[ "$output" == *"stderr error message"* ]]
}

@test "parrot_log: all levels pass at DEBUG level" {
    export PARROT_LOG_LEVEL="DEBUG"
    export PARROT_SERVER_LOG="$TEST_DIR/logs/debug_test.log"
    parrot_log "DEBUG" "debug msg"
    parrot_log "INFO" "info msg"
    parrot_log "WARN" "warn msg"
    parrot_log "ERROR" "error msg"
    grep -q "debug msg" "$TEST_DIR/logs/debug_test.log"
    grep -q "info msg"  "$TEST_DIR/logs/debug_test.log"
    grep -q "warn msg"  "$TEST_DIR/logs/debug_test.log"
    grep -q "error msg" "$TEST_DIR/logs/debug_test.log"
}
