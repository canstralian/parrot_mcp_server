#!/usr/bin/env bash
# test_logging.sh - Test harness for logging and metrics system
# Usage: ./test_logging.sh
#
# This script tests:
#   1. Structured JSON logging via logging.sh
#   2. Tool execution wrapper and metrics generation via wrap_tool_exec.sh
#   3. Log search functionality via search_logs.sh
#   4. Metrics file creation and format

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test functions
print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Setup test environment
setup_test_env() {
    print_test "Setting up test environment..."
    
    # Use test-specific directories
    export PARROT_LOG_FILE="${BASE_DIR}/logs/test_parrot.log"
    export PARROT_METRICS_DIR="${BASE_DIR}/metrics/test"
    
    # Clean up any previous test artifacts
    rm -f "$PARROT_LOG_FILE"
    rm -rf "$PARROT_METRICS_DIR"
    mkdir -p "$(dirname "$PARROT_LOG_FILE")"
    mkdir -p "$PARROT_METRICS_DIR"
    
    print_pass "Test environment setup complete"
}

# Test 1: Basic JSON logging
test_basic_logging() {
    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "Testing basic JSON logging..."
    
    # Source logging functions
    # shellcheck source=../scripts/logging.sh
    source "${BASE_DIR}/scripts/logging.sh"
    
    # Log a test message
    log_info "Test message" test_key=test_value
    
    # Check if log file exists and contains JSON
    if [ ! -f "$PARROT_LOG_FILE" ]; then
        print_fail "Log file not created"
        return 1
    fi
    
    # Check if log entry is valid JSON and contains expected fields
    local last_entry
    last_entry=$(tail -n 1 "$PARROT_LOG_FILE")
    
    if echo "$last_entry" | grep -q '"message":"Test message"' && \
       echo "$last_entry" | grep -q '"test_key":"test_value"' && \
       echo "$last_entry" | grep -q '"timestamp"' && \
       echo "$last_entry" | grep -q '"level":"INFO"'; then
        print_pass "Basic JSON logging works correctly"
        return 0
    else
        print_fail "Log entry missing expected fields: $last_entry"
        return 1
    fi
}

# Test 2: Sensitive data sanitization
test_sanitization() {
    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "Testing sensitive data sanitization..."
    
    # Source logging functions
    # shellcheck source=../scripts/logging.sh
    source "${BASE_DIR}/scripts/logging.sh"
    
    # Log with sensitive data
    log_info "Login attempt" username=alice password=secret123 api_token=abc123
    
    local last_entry
    last_entry=$(tail -n 1 "$PARROT_LOG_FILE")
    
    # Check that sensitive fields are redacted
    if echo "$last_entry" | grep -q '"password":"\[REDACTED\]"' && \
       echo "$last_entry" | grep -q '"api_token":"\[REDACTED\]"' && \
       echo "$last_entry" | grep -q '"username":"alice"'; then
        print_pass "Sensitive data sanitization works correctly"
        return 0
    else
        print_fail "Sensitive data not properly redacted: $last_entry"
        return 1
    fi
}

# Test 3: Tool execution wrapper - success case
test_wrap_tool_success() {
    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "Testing tool execution wrapper (success case)..."
    
    # Create a simple test script
    local test_script="${BASE_DIR}/logs/test_script_success.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
echo "Test script executed successfully"
exit 0
EOF
    chmod +x "$test_script"
    
    # Run via wrapper
    "${BASE_DIR}/scripts/wrap_tool_exec.sh" test_tool test_user /test/target "$test_script"
    
    # Check log file for tool execution entry
    if grep -q '"tool":"test_tool"' "$PARROT_LOG_FILE" && \
       grep -q '"status":"success"' "$PARROT_LOG_FILE"; then
        print_pass "Tool wrapper logged successful execution"
    else
        print_fail "Tool execution not properly logged"
        return 1
    fi
    
    # Check metrics file
    local metrics_file="${PARROT_METRICS_DIR}/test_tool.prom"
    if [ -f "$metrics_file" ]; then
        if grep -q 'tool_executions_total{tool="test_tool",status="success"} 1' "$metrics_file" && \
           grep -q 'tool_errors_total{tool="test_tool"} 0' "$metrics_file" && \
           grep -q 'tool_last_duration_ms{tool="test_tool"}' "$metrics_file"; then
            print_pass "Tool wrapper generated correct metrics for success"
            return 0
        else
            print_fail "Metrics file has incorrect values"
            cat "$metrics_file"
            return 1
        fi
    else
        print_fail "Metrics file not created: $metrics_file"
        return 1
    fi
}

# Test 4: Tool execution wrapper - failure case
test_wrap_tool_failure() {
    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "Testing tool execution wrapper (failure case)..."
    
    # Create a failing test script
    local test_script="${BASE_DIR}/logs/test_script_failure.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
echo "Test script failed"
exit 1
EOF
    chmod +x "$test_script"
    
    # Run via wrapper (expect failure)
    "${BASE_DIR}/scripts/wrap_tool_exec.sh" test_tool_fail test_user /test/target "$test_script" || true
    
    # Check log file for failure status
    if grep -q '"tool":"test_tool_fail"' "$PARROT_LOG_FILE" && \
       grep -q '"status":"failure"' "$PARROT_LOG_FILE" && \
       grep -q '"exit_code":"1"' "$PARROT_LOG_FILE"; then
        print_pass "Tool wrapper logged failed execution"
    else
        print_fail "Tool failure not properly logged"
        return 1
    fi
    
    # Check metrics file
    local metrics_file="${PARROT_METRICS_DIR}/test_tool_fail.prom"
    if [ -f "$metrics_file" ]; then
        if grep -q 'tool_executions_total{tool="test_tool_fail",status="failure"} 1' "$metrics_file" && \
           grep -q 'tool_errors_total{tool="test_tool_fail"} 1' "$metrics_file"; then
            print_pass "Tool wrapper generated correct metrics for failure"
            return 0
        else
            print_fail "Metrics file has incorrect values for failure"
            cat "$metrics_file"
            return 1
        fi
    else
        print_fail "Metrics file not created for failure case: $metrics_file"
        return 1
    fi
}

# Test 5: Log search functionality
test_log_search() {
    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "Testing log search functionality..."
    
    # Add some test log entries with different attributes
    # shellcheck source=../scripts/logging.sh
    source "${BASE_DIR}/scripts/logging.sh"
    
    log_info "Search test 1" tool=search_test_tool user=alice status=success
    log_error "Search test 2" tool=search_test_tool user=bob status=failure
    log_info "Search test 3" tool=other_tool user=alice status=success
    
    # Test tool filter
    local search_result
    search_result=$("${BASE_DIR}/scripts/search_logs.sh" --tool=search_test_tool 2>/dev/null | wc -l)
    if [ "$search_result" -eq 2 ]; then
        print_pass "Log search by tool works correctly"
    else
        print_fail "Log search by tool returned $search_result entries, expected 2"
        return 1
    fi
    
    # Test user filter
    search_result=$("${BASE_DIR}/scripts/search_logs.sh" --user=alice 2>/dev/null | wc -l)
    if [ "$search_result" -ge 2 ]; then
        print_pass "Log search by user works correctly"
    else
        print_fail "Log search by user returned $search_result entries, expected at least 2"
        return 1
    fi
    
    # Test status filter
    search_result=$("${BASE_DIR}/scripts/search_logs.sh" --status=failure 2>/dev/null | wc -l)
    if [ "$search_result" -ge 1 ]; then
        print_pass "Log search by status works correctly"
        return 0
    else
        print_fail "Log search by status returned $search_result entries, expected at least 1"
        return 1
    fi
}

# Test 6: Multiple executions accumulate metrics
test_metrics_accumulation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    print_test "Testing metrics accumulation across multiple executions..."
    
    # Create a test script
    local test_script="${BASE_DIR}/logs/test_script_multi.sh"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
echo "Multiple execution test"
exit 0
EOF
    chmod +x "$test_script"
    
    # Run wrapper multiple times
    for i in {1..3}; do
        "${BASE_DIR}/scripts/wrap_tool_exec.sh" test_tool_multi test_user /test/target "$test_script" >/dev/null
    done
    
    # Check that counter accumulated
    local metrics_file="${PARROT_METRICS_DIR}/test_tool_multi.prom"
    if grep -q 'tool_executions_total{tool="test_tool_multi",status="success"} 3' "$metrics_file"; then
        print_pass "Metrics correctly accumulated across multiple executions"
        return 0
    else
        print_fail "Metrics did not accumulate correctly"
        cat "$metrics_file"
        return 1
    fi
}

# Cleanup test environment
cleanup_test_env() {
    print_test "Cleaning up test environment..."
    
    # Show log and metrics for manual inspection
    echo ""
    echo "==== Test Log Entries ===="
    tail -20 "$PARROT_LOG_FILE" || true
    echo ""
    echo "==== Sample Metrics File ===="
    if [ -f "${PARROT_METRICS_DIR}/test_tool.prom" ]; then
        cat "${PARROT_METRICS_DIR}/test_tool.prom"
    fi
    echo ""
    
    # Note: Not deleting test artifacts for manual inspection
    print_pass "Test artifacts preserved in logs/ and metrics/test/ for inspection"
}

# Main test execution
main() {
    echo "=========================================="
    echo "  Logging and Metrics Test Suite"
    echo "=========================================="
    echo ""
    
    setup_test_env
    
    # Run tests and catch failures
    test_basic_logging || true
    test_sanitization || true
    test_wrap_tool_success || true
    test_wrap_tool_failure || true
    test_log_search || true
    test_metrics_accumulation || true
    
    cleanup_test_env
    
    echo ""
    echo "=========================================="
    echo "  Test Results"
    echo "=========================================="
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
main "$@"
