#!/usr/bin/env bash
# test_helpers.bash - Common test helper functions and fixtures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result counters
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# Helper: Print colored test result
print_result() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        PASS)
            echo -e "${GREEN}[PASS]${NC} $message"
            ((TEST_PASSED++))
            ;;
        FAIL)
            echo -e "${RED}[FAIL]${NC} $message"
            ((TEST_FAILED++))
            ;;
        SKIP)
            echo -e "${YELLOW}[SKIP]${NC} $message"
            ((TEST_SKIPPED++))
            ;;
        *)
            echo "[INFO] $message"
            ;;
    esac
}

# Helper: Print test summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo -e "${GREEN}Passed:${NC}  $TEST_PASSED"
    echo -e "${RED}Failed:${NC}  $TEST_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TEST_SKIPPED"
    echo "========================================"
    
    if [ "$TEST_FAILED" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Helper: Wait for file with timeout
wait_for_file() {
    local file="$1"
    local timeout="${2:-10}"
    local elapsed=0
    
    while [ ! -f "$file" ] && [ "$elapsed" -lt "$timeout" ]; do
        sleep 1
        ((elapsed++))
    done
    
    [ -f "$file" ]
}

# Helper: Wait for process with timeout
wait_for_process() {
    local pid="$1"
    local timeout="${2:-10}"
    local elapsed=0
    
    while ps -p "$pid" >/dev/null 2>&1 && [ "$elapsed" -lt "$timeout" ]; do
        sleep 1
        ((elapsed++))
    done
    
    ! ps -p "$pid" >/dev/null 2>&1
}

# Helper: Create test MCP message
create_mcp_message() {
    local type="$1"
    local content="$2"
    local output_file="$3"
    
    cat > "$output_file" <<EOF
{
    "type": "$type",
    "content": "$content",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "msgid": "test_$(date +%s%N)"
}
EOF
}

# Helper: Validate JSON structure
validate_json() {
    local file="$1"
    
    if command -v jq >/dev/null 2>&1; then
        jq empty "$file" >/dev/null 2>&1
        return $?
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import json; json.load(open('$file'))" >/dev/null 2>&1
        return $?
    else
        # Basic check if jq/python not available
        grep -qE '^\{.*\}$' "$file" && grep -q '"' "$file"
        return $?
    fi
}

# Helper: Clean up test artifacts
cleanup_test_artifacts() {
    local pattern="${1:-mcp_test_}"
    
    # Clean up temp files
    rm -f /tmp/"${pattern}"* 2>/dev/null || true
    
    # Clean up test log files
    rm -f ./logs/test_*.log 2>/dev/null || true
}

# Helper: Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper: Get timestamp
get_timestamp() {
    date +%Y-%m-%d_%H-%M-%S
}

# Helper: Create test log directory
setup_test_logging() {
    local test_name="$1"
    local log_dir="${TEST_LOG_DIR:-./logs/tests}"
    
    mkdir -p "$log_dir"
    export TEST_LOG_FILE="$log_dir/${test_name}_$(get_timestamp).log"
    
    echo "Test: $test_name" > "$TEST_LOG_FILE"
    echo "Started: $(date)" >> "$TEST_LOG_FILE"
    echo "========================================" >> "$TEST_LOG_FILE"
}

# Helper: Verify script has valid shebang
check_shebang() {
    local script="$1"
    
    [ -f "$script" ] || return 1
    
    head -n 1 "$script" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash'
}

# Helper: Verify script is executable
check_executable() {
    local script="$1"
    
    [ -x "$script" ]
}

# Helper: Test network connectivity (for integration tests)
check_network() {
    local host="${1:-8.8.8.8}"
    
    ping -c 1 -W 2 "$host" >/dev/null 2>&1
}

# Helper: Generate random test data
generate_test_string() {
    local length="${1:-16}"
    
    if command_exists openssl; then
        openssl rand -hex "$((length / 2))"
    else
        head /dev/urandom | tr -dc A-Za-z0-9 | head -c "$length"
    fi
}

# Helper: Create mock configuration
create_mock_config() {
    local config_file="$1"
    
    cat > "$config_file" <<'EOF'
# Mock test configuration
export PARROT_DEBUG="false"
export PARROT_LOG_DIR="./logs"
export PARROT_ALERT_EMAIL=""
export PARROT_BACKUP_DIR="./backups"
export PARROT_MAX_LOG_SIZE="10M"
export PARROT_LOG_RETENTION_DAYS="30"
EOF
}

# Helper: Verify log format
check_log_format() {
    local log_file="$1"
    
    [ -f "$log_file" ] || return 1
    
    # Check for timestamp pattern
    grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$log_file"
}

# Helper: Count log entries by level
count_log_level() {
    local log_file="$1"
    local level="$2"
    
    [ -f "$log_file" ] || return 1
    
    grep -c "\[$level\]" "$log_file" 2>/dev/null || echo 0
}

# Helper: Extract message IDs from log
extract_message_ids() {
    local log_file="$1"
    
    [ -f "$log_file" ] || return 1
    
    grep -oE 'msgid:[0-9]+' "$log_file" | cut -d: -f2 | sort -u
}

# Helper: Simulate concurrent requests
simulate_concurrent_load() {
    local script="$1"
    local count="${2:-5}"
    local pids=()
    
    for i in $(seq 1 "$count"); do
        $script >/dev/null 2>&1 &
        pids+=($!)
    done
    
    # Wait for all to complete
    local failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || ((failed++))
    done
    
    return "$failed"
}

# Helper: Verify file permissions
check_file_permissions() {
    local file="$1"
    local expected_perms="$2"
    
    [ -f "$file" ] || return 1
    
    local actual_perms
    actual_perms=$(stat -c %a "$file")
    
    [ "$actual_perms" = "$expected_perms" ]
}

# Helper: Create test workspace
create_test_workspace() {
    local workspace_dir="${1:-$(mktemp -d)}"
    
    mkdir -p "$workspace_dir"/{logs,backups,tmp,config}
    
    echo "$workspace_dir"
}

# Helper: Cleanup test workspace
cleanup_test_workspace() {
    local workspace_dir="$1"
    
    [ -n "$workspace_dir" ] && [ -d "$workspace_dir" ] && rm -rf "$workspace_dir"
}

# Helper: Mock external command
mock_command() {
    local command_name="$1"
    local mock_output="$2"
    local mock_exit_code="${3:-0}"
    
    local mock_script="/tmp/mock_${command_name}_$$"
    
    cat > "$mock_script" <<EOF
#!/bin/bash
echo "$mock_output"
exit $mock_exit_code
EOF
    
    chmod +x "$mock_script"
    echo "$mock_script"
}

# Helper: Restore original command
restore_command() {
    local mock_script="$1"
    
    [ -f "$mock_script" ] && rm -f "$mock_script"
}

# Helper: Assert equals
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [ "$expected" = "$actual" ]; then
        print_result PASS "$message"
        return 0
    else
        print_result FAIL "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

# Helper: Assert not equals
assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [ "$expected" != "$actual" ]; then
        print_result PASS "$message"
        return 0
    else
        print_result FAIL "$message: values should not be equal"
        return 1
    fi
}

# Helper: Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"
    
    if [ -f "$file" ]; then
        print_result PASS "$message"
        return 0
    else
        print_result FAIL "$message"
        return 1
    fi
}

# Helper: Assert file not exists
assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist: $file}"
    
    if [ ! -f "$file" ]; then
        print_result PASS "$message"
        return 0
    else
        print_result FAIL "$message"
        return 1
    fi
}

# Helper: Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        print_result PASS "$message"
        return 0
    else
        print_result FAIL "$message: '$haystack' does not contain '$needle'"
        return 1
    fi
}

# Export functions for use in tests
export -f print_result
export -f print_summary
export -f wait_for_file
export -f wait_for_process
export -f create_mcp_message
export -f validate_json
export -f cleanup_test_artifacts
export -f command_exists
export -f get_timestamp
export -f setup_test_logging
export -f check_shebang
export -f check_executable
export -f check_network
export -f generate_test_string
export -f create_mock_config
export -f check_log_format
export -f count_log_level
export -f extract_message_ids
export -f simulate_concurrent_load
export -f check_file_permissions
export -f create_test_workspace
export -f cleanup_test_workspace
export -f mock_command
export -f restore_command
export -f assert_equals
export -f assert_not_equals
export -f assert_file_exists
export -f assert_file_not_exists
export -f assert_contains
