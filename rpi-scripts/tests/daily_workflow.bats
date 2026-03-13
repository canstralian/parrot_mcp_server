#!/usr/bin/env bats
# daily_workflow.bats - Tests for scripts/daily_workflow.sh
#
# Strategy:
#   daily_workflow.sh sets SCRIPT_DIR="$(dirname "$0")/.." and then calls
#   "$SCRIPT_DIR/cli.sh" for each task.  We copy the real script into a temp
#   directory so that dirname resolves there, then place a controllable fake
#   cli.sh beside it.
#
#   LOG_FILE="./logs/daily_workflow.log" is relative to CWD, so we cd into
#   the temp directory before each test.

REAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)/daily_workflow.sh"

setup() {
    # Build directory layout:
    #   TEST_DIR/
    #     rpi-scripts/
    #       cli.sh         ← controllable fake
    #       scripts/
    #         daily_workflow.sh  ← copy of the real script
    #     logs/            ← LOG_FILE writes here (relative to CWD)
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/rpi-scripts/scripts"
    mkdir -p "$TEST_DIR/logs"
    mkdir -p "$TEST_DIR/bin"   # for fake commands (mail, etc.)

    cp "$REAL_SCRIPT" "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    chmod +x "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"

    # Default fake cli.sh: succeeds for any task
    _write_cli_sh "exit 0"

    # Fake 'mail' so email-sending code does not fail
    cat > "$TEST_DIR/bin/mail" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_DIR/bin/mail"

    ORIG_DIR="$(pwd)"
    export PATH="$TEST_DIR/bin:$PATH"

    # Run the script from TEST_DIR so ./logs/ resolves correctly
    cd "$TEST_DIR"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# Write a cli.sh that executes the given body for every invocation.
_write_cli_sh() {
    local body="$1"
    cat > "$TEST_DIR/rpi-scripts/cli.sh" << EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$TEST_DIR/rpi-scripts/cli.sh"
}

# ============================================================================
# HAPPY PATH
# ============================================================================

@test "daily_workflow: exits 0 when all tasks succeed" {
    _write_cli_sh "exit 0"
    run bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    [ "$status" -eq 0 ]
}

@test "daily_workflow: creates log file on successful run" {
    run bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    [ -f "$TEST_DIR/logs/daily_workflow.log" ]
}

@test "daily_workflow: log contains start marker" {
    bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    grep -q "Starting daily maintenance workflow" "$TEST_DIR/logs/daily_workflow.log"
}

@test "daily_workflow: log contains completion marker on success" {
    bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    grep -q "Daily maintenance workflow completed successfully" \
        "$TEST_DIR/logs/daily_workflow.log"
}

@test "daily_workflow: log entries include timestamps" {
    bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' \
        "$TEST_DIR/logs/daily_workflow.log"
}

# ============================================================================
# RETRY LOGIC
# ============================================================================

@test "daily_workflow: retries a failing task" {
    # cli.sh fails on first 2 calls, succeeds from call 3 onward
    COUNTER_FILE="$TEST_DIR/call_count"
    echo 0 > "$COUNTER_FILE"

    cat > "$TEST_DIR/rpi-scripts/cli.sh" << EOF
#!/usr/bin/env bash
count=\$(cat "$COUNTER_FILE")
count=\$((count + 1))
echo "\$count" > "$COUNTER_FILE"
if [ "\$count" -le 2 ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_DIR/rpi-scripts/cli.sh"

    # Override sleep so the test doesn't wait 60 s between retries
    cat > "$TEST_DIR/bin/sleep" << 'SLEEPEOF'
#!/usr/bin/env bash
exit 0
SLEEPEOF
    chmod +x "$TEST_DIR/bin/sleep"

    run bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    [ "$status" -eq 0 ]
    # cli.sh was called more than once
    final_count=$(cat "$COUNTER_FILE")
    [ "$final_count" -gt 1 ]
}

@test "daily_workflow: aborts after max retries exhausted" {
    # cli.sh always fails → run_task should call error_exit
    _write_cli_sh "exit 1"

    cat > "$TEST_DIR/bin/sleep" << 'SLEEPEOF'
#!/usr/bin/env bash
exit 0
SLEEPEOF
    chmod +x "$TEST_DIR/bin/sleep"

    run bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    [ "$status" -ne 0 ]
}

@test "daily_workflow: logs task failure message on retry" {
    _write_cli_sh "exit 1"

    cat > "$TEST_DIR/bin/sleep" << 'SLEEPEOF'
#!/usr/bin/env bash
exit 0
SLEEPEOF
    chmod +x "$TEST_DIR/bin/sleep"

    bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh" || true
    grep -q "failed" "$TEST_DIR/logs/daily_workflow.log"
}

# ============================================================================
# SYSTEM UPDATE (OPTIONAL — FAILURE DOES NOT ABORT)
# ============================================================================

@test "daily_workflow: continues when system_update fails" {
    # cli.sh fails only when called with 'system_update', succeeds otherwise
    CALL_ARGS_FILE="$TEST_DIR/call_args"
    cat > "$TEST_DIR/rpi-scripts/cli.sh" << EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALL_ARGS_FILE"
if [[ "\$*" == *system_update* ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_DIR/rpi-scripts/cli.sh"

    run bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"
    # Workflow should still complete successfully
    [ "$status" -eq 0 ]
    grep -q "completed successfully" "$TEST_DIR/logs/daily_workflow.log"
}

@test "daily_workflow: logs warning when system_update fails" {
    cat > "$TEST_DIR/rpi-scripts/cli.sh" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *system_update* ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_DIR/rpi-scripts/cli.sh"

    bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh" || true
    grep -q "WARNING" "$TEST_DIR/logs/daily_workflow.log"
}

# ============================================================================
# EMAIL NOTIFICATIONS
# ============================================================================

@test "daily_workflow: sends success email when NOTIFY_EMAIL is set" {
    MAIL_LOG="$TEST_DIR/mail_calls.log"
    cat > "$TEST_DIR/bin/mail" << EOF
#!/usr/bin/env bash
echo "MAIL CALLED: \$*" >> "$MAIL_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/mail"

    _write_cli_sh "exit 0"
    NOTIFY_EMAIL="ops@example.com" bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"

    [ -f "$MAIL_LOG" ]
    grep -q "MAIL CALLED" "$MAIL_LOG"
}

@test "daily_workflow: no email sent when NOTIFY_EMAIL is empty" {
    MAIL_LOG="$TEST_DIR/mail_calls.log"
    cat > "$TEST_DIR/bin/mail" << EOF
#!/usr/bin/env bash
echo "MAIL CALLED" >> "$MAIL_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/mail"

    _write_cli_sh "exit 0"
    bash "$TEST_DIR/rpi-scripts/scripts/daily_workflow.sh"

    [ ! -f "$MAIL_LOG" ]
}
