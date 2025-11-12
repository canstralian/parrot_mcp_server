#!/usr/bin/env bats
# Tests for enhanced logging and analytics system

setup() {
  # Source common config for testing
  source "$(dirname "$BATS_TEST_DIRNAME")/common_config.sh"
  
  # Create temporary test directory
  export TEST_LOG_DIR=$(mktemp -d)
  export PARROT_LOG_DIR="$TEST_LOG_DIR"
  export PARROT_JSON_LOG="$TEST_LOG_DIR/test.json.log"
  export PARROT_AUDIT_LOG="$TEST_LOG_DIR/test_audit.log"
  export PARROT_METRICS_LOG="$TEST_LOG_DIR/test_metrics.log"
  export PARROT_SERVER_LOG="$TEST_LOG_DIR/test.log"
  
  # Initialize log directory
  parrot_init_log_dir
}

teardown() {
  # Clean up temporary directory
  rm -rf "$TEST_LOG_DIR"
}

@test "JSON logging creates valid JSON" {
  parrot_log_json "INFO" "Test message" "key1=value1" "key2=value2"
  
  [ -f "$PARROT_JSON_LOG" ]
  
  # Validate JSON syntax
  run jq empty "$PARROT_JSON_LOG"
  [ "$status" -eq 0 ]
  
  # Check for expected fields
  run jq -r '.level' "$PARROT_JSON_LOG"
  [ "$output" = "INFO" ]
  
  run jq -r '.message' "$PARROT_JSON_LOG"
  [ "$output" = "Test message" ]
  
  run jq -r '.key1' "$PARROT_JSON_LOG"
  [ "$output" = "value1" ]
}

@test "JSON logging includes all standard fields" {
  parrot_log_json "DEBUG" "Debug message"
  
  # Check for timestamp, level, message, msgid, hostname, user, pid
  run jq 'has("timestamp")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
  
  run jq 'has("level")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
  
  run jq 'has("message")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
  
  run jq 'has("msgid")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
  
  run jq 'has("hostname")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
  
  run jq 'has("user")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
  
  run jq 'has("pid")' "$PARROT_JSON_LOG"
  [[ "$output" == "true" ]]
}

@test "All log levels work correctly" {
  parrot_debug "Debug message"
  parrot_info "Info message"
  parrot_warn "Warning message"
  parrot_error "Error message"
  parrot_critical "Critical message"
  
  [ -f "$PARROT_SERVER_LOG" ]
  
  run grep -c "DEBUG" "$PARROT_SERVER_LOG"
  [ "$output" -ge 0 ]
  
  run grep -c "INFO" "$PARROT_SERVER_LOG"
  [ "$output" -ge 0 ]
  
  run grep -c "WARN" "$PARROT_SERVER_LOG"
  [ "$output" -ge 0 ]
  
  run grep -c "ERROR" "$PARROT_SERVER_LOG"
  [ "$output" -ge 0 ]
  
  run grep -c "CRITICAL" "$PARROT_SERVER_LOG"
  [ "$output" -ge 0 ]
}

@test "Credential sanitization works" {
  local test_value="password=secret123 token=abc123xyz"
  run parrot_sanitize_log_value "$test_value"
  
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"secret123"* ]]
  [[ "$output" != *"abc123xyz"* ]]
}

@test "Bearer token sanitization works" {
  local test_value="Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
  run parrot_sanitize_log_value "$test_value"
  
  [[ "$output" == *"Bearer [REDACTED]"* ]]
  [[ "$output" != *"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"* ]]
}

@test "Metrics timing functions work" {
  local start_time
  start_time=$(parrot_metrics_start)
  
  # Simulate some work
  sleep 0.1
  
  local duration
  duration=$(parrot_metrics_end "$start_time" "test_operation" "success")
  
  # Duration should be at least 100ms
  [ "$duration" -ge 100 ]
  
  # Check metrics log file was created
  [ -f "$PARROT_METRICS_LOG" ]
  
  # Check metrics format (Prometheus format)
  run grep "parrot_operation_duration_milliseconds" "$PARROT_METRICS_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"operation=\"test_operation\""* ]]
  [[ "$output" == *"status=\"success\""* ]]
}

@test "Audit logging creates entries" {
  parrot_audit_log "test_action" "test_target" "success" "extra=data"
  
  [ -f "$PARROT_AUDIT_LOG" ]
  [ -f "$PARROT_JSON_LOG" ]
  
  # Check audit log format (pipe-delimited)
  run cat "$PARROT_AUDIT_LOG"
  [[ "$output" == *"test_action"* ]]
  [[ "$output" == *"test_target"* ]]
  [[ "$output" == *"success"* ]]
  
  # Check JSON log has audit fields
  run jq -r '.audit_action' "$PARROT_JSON_LOG"
  [ "$output" = "test_action" ]
  
  run jq -r '.audit_result' "$PARROT_JSON_LOG"
  [ "$output" = "success" ]
}

@test "Audit log sanitizes sensitive data" {
  parrot_audit_log "login" "password=secret123" "success"
  
  # Check that password is redacted in audit log
  run cat "$PARROT_AUDIT_LOG"
  [[ "$output" != *"secret123"* ]]
  [[ "$output" == *"[REDACTED]"* ]]
}

@test "JSON logging escapes quotes properly" {
  parrot_log_json "INFO" "Message with \"quotes\" in it" "key=value with \"quotes\""
  
  # Should still be valid JSON
  run jq empty "$PARROT_JSON_LOG"
  [ "$status" -eq 0 ]
  
  # Check message was properly escaped
  run jq -r '.message' "$PARROT_JSON_LOG"
  [[ "$output" == *"quotes"* ]]
}

@test "Log levels filter correctly" {
  export PARROT_LOG_LEVEL="ERROR"
  
  parrot_debug "Debug message"
  parrot_info "Info message"
  parrot_error "Error message"
  
  # Only ERROR should be logged
  run cat "$PARROT_SERVER_LOG"
  [[ "$output" != *"Debug message"* ]]
  [[ "$output" != *"Info message"* ]]
  [[ "$output" == *"Error message"* ]]
}

@test "Metrics export script works" {
  # Create some test data
  parrot_log_json "INFO" "Operation completed" "operation=test_op" "duration_ms=100" "status=success"
  parrot_log_json "INFO" "Operation completed" "operation=test_op" "duration_ms=200" "status=success"
  parrot_log_json "ERROR" "Operation failed" "operation=test_op" "status=error"
  
  # Run metrics export
  run bash "$(dirname "$BATS_TEST_DIRNAME")/scripts/metrics_export.sh" --format json
  [ "$status" -eq 0 ]
  
  # Check JSON output is valid
  echo "$output" | jq empty
}

@test "Log search script filters by level" {
  # Create test logs
  parrot_log_json "INFO" "Info message 1"
  parrot_log_json "ERROR" "Error message 1"
  parrot_log_json "INFO" "Info message 2"
  
  # Search for ERROR logs
  run bash "$(dirname "$BATS_TEST_DIRNAME")/scripts/log_search.sh" --level ERROR --file "$PARROT_JSON_LOG" --format text
  [ "$status" -eq 0 ]
  [[ "$output" == *"Error message 1"* ]]
  [[ "$output" != *"Info message"* ]]
}

@test "Log search script filters by user" {
  # Create test logs with different users
  export USER="testuser1"
  parrot_log_json "INFO" "Message from user 1"
  
  export USER="testuser2"
  parrot_log_json "INFO" "Message from user 2"
  
  # Search for specific user
  run bash "$(dirname "$BATS_TEST_DIRNAME")/scripts/log_search.sh" --user testuser1 --file "$PARROT_JSON_LOG" --format text
  [ "$status" -eq 0 ]
  [[ "$output" == *"testuser1"* ]]
  [[ "$output" != *"testuser2"* ]]
}

@test "Log rotation creates rotated files" {
  # Create a large log file
  for i in {1..1000}; do
    echo "Log line $i with some padding to make it larger" >> "$PARROT_SERVER_LOG"
  done
  
  # Make sure file is large enough
  local size
  size=$(stat -c%s "$PARROT_SERVER_LOG" 2>/dev/null || stat -f%z "$PARROT_SERVER_LOG")
  [ "$size" -gt 10000 ]
  
  # Run log rotation with small size threshold
  run bash "$(dirname "$BATS_TEST_DIRNAME")/scripts/log_rotate.sh" --size 0.01 --count 3
  [ "$status" -eq 0 ]
  
  # Check that rotated file was created
  local rotated_count
  rotated_count=$(ls -1 "$PARROT_SERVER_LOG".*.gz 2>/dev/null | wc -l)
  [ "$rotated_count" -ge 1 ]
}
