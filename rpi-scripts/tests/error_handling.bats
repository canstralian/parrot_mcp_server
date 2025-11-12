#!/usr/bin/env bats
# error_handling.bats - Tests for error handling and validation functions

# Load error handling module
setup() {
    cd "$(dirname "$BATS_TEST_FILENAME")/.."
    # shellcheck source=../error_handling.sh
    source ./error_handling.sh
    
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
# ERROR CODE MAPPING TESTS
# ============================================================================

@test "parrot_error_code_to_name: maps SUCCESS" {
    run parrot_error_code_to_name 0
    [ "$status" -eq 0 ]
    [ "$output" = "SUCCESS" ]
}

@test "parrot_error_code_to_name: maps INVALID_INPUT" {
    run parrot_error_code_to_name 10
    [ "$status" -eq 0 ]
    [ "$output" = "INVALID_INPUT" ]
}

@test "parrot_error_code_to_name: maps TOOL_FAILED" {
    run parrot_error_code_to_name 20
    [ "$status" -eq 0 ]
    [ "$output" = "TOOL_FAILED" ]
}

@test "parrot_error_code_to_name: maps unknown codes to UNKNOWN" {
    run parrot_error_code_to_name 999
    [ "$status" -eq 0 ]
    [ "$output" = "UNKNOWN" ]
}

# ============================================================================
# REQUEST ID GENERATION TESTS
# ============================================================================

@test "parrot_generate_request_id: generates valid ID" {
    run parrot_generate_request_id
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^req_[0-9]+_[0-9]+_[0-9]+$ ]]
}

@test "parrot_generate_request_id: accepts custom prefix" {
    run parrot_generate_request_id "test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^test_[0-9]+_[0-9]+_[0-9]+$ ]]
}

@test "parrot_generate_request_id: generates unique IDs" {
    local id1 id2
    id1=$(parrot_generate_request_id)
    id2=$(parrot_generate_request_id)
    [ "$id1" != "$id2" ]
}

# ============================================================================
# ERROR RESPONSE FORMATTING TESTS
# ============================================================================

@test "parrot_format_error_response: creates valid JSON structure" {
    run parrot_format_error_response 10 "Test error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "error" ]]
    [[ "$output" =~ "INVALID_INPUT" ]]
    [[ "$output" =~ "Test error message" ]]
}

@test "parrot_format_error_response: includes field details" {
    run parrot_format_error_response 15 "Field required" "target" "null" "string"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \"field\":\"target\" ]]
    [[ "$output" =~ \"provided\":null ]]
    [[ "$output" =~ \"expected\":\"string\" ]]
}

@test "parrot_format_error_response: includes timestamp" {
    run parrot_format_error_response 10 "Test error"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "timestamp" ]]
    [[ "$output" =~ "Z" ]]
}

# ============================================================================
# IPv4 VALIDATION TESTS
# ============================================================================

@test "parrot_validate_ipv4: accepts valid IPv4 address" {
    run parrot_validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_ipv4: accepts localhost" {
    run parrot_validate_ipv4 "127.0.0.1"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_ipv4: accepts broadcast address" {
    run parrot_validate_ipv4 "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_ipv4: accepts zero address" {
    run parrot_validate_ipv4 "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_ipv4: rejects invalid octet value" {
    run parrot_validate_ipv4 "192.168.1.256"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_ipv4: rejects negative octet" {
    run parrot_validate_ipv4 "192.168.-1.1"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_ipv4: rejects too few octets" {
    run parrot_validate_ipv4 "192.168.1"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_ipv4: rejects too many octets" {
    run parrot_validate_ipv4 "192.168.1.1.1"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_ipv4: rejects non-numeric octets" {
    run parrot_validate_ipv4 "192.168.abc.1"
    [ "$status" -eq 1 ]
}

# ============================================================================
# HOSTNAME VALIDATION TESTS
# ============================================================================

@test "parrot_validate_hostname: accepts valid hostname" {
    run parrot_validate_hostname "example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_hostname: accepts subdomain" {
    run parrot_validate_hostname "sub.example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_hostname: accepts hyphenated hostname" {
    run parrot_validate_hostname "my-server.example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_hostname: accepts single label hostname" {
    run parrot_validate_hostname "localhost"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_hostname: rejects hostname starting with hyphen" {
    run parrot_validate_hostname "-invalid.example.com"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_hostname: rejects hostname ending with hyphen" {
    run parrot_validate_hostname "invalid-.example.com"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_hostname: rejects hostname with special characters" {
    run parrot_validate_hostname "invalid_host.example.com"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_hostname: rejects empty hostname" {
    run parrot_validate_hostname ""
    [ "$status" -eq 1 ]
}

# ============================================================================
# PORT VALIDATION TESTS
# ============================================================================

@test "parrot_validate_port: accepts valid port 80" {
    run parrot_validate_port "80"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port: accepts port 1" {
    run parrot_validate_port "1"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port: accepts port 65535" {
    run parrot_validate_port "65535"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port: rejects port 0" {
    run parrot_validate_port "0"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_port: rejects port > 65535" {
    run parrot_validate_port "65536"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_port: rejects negative port" {
    run parrot_validate_port "-1"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_port: rejects non-numeric port" {
    run parrot_validate_port "abc"
    [ "$status" -eq 1 ]
}

# ============================================================================
# PORT RANGE VALIDATION TESTS
# ============================================================================

@test "parrot_validate_port_range: accepts single port" {
    run parrot_validate_port_range "80"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port_range: accepts port range" {
    run parrot_validate_port_range "80-443"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port_range: accepts comma-separated ports" {
    run parrot_validate_port_range "22,80,443"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port_range: accepts mixed format" {
    run parrot_validate_port_range "22,80-443,8080"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_port_range: rejects invalid range (start > end)" {
    run parrot_validate_port_range "443-80"
    [ "$status" -eq 1 ]
}

@test "parrot_validate_port_range: rejects invalid port in range" {
    run parrot_validate_port_range "80-65536"
    [ "$status" -eq 1 ]
}

# ============================================================================
# TARGET VALIDATION TESTS
# ============================================================================

@test "parrot_validate_target: accepts valid IP" {
    run parrot_validate_target "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_target: accepts valid hostname" {
    run parrot_validate_target "example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_target: rejects invalid target" {
    run parrot_validate_target "invalid_target!"
    [ "$status" -eq 1 ]
}

# ============================================================================
# TARGET SANITIZATION TESTS
# ============================================================================

@test "parrot_sanitize_target: preserves valid characters" {
    run parrot_sanitize_target "example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "example.com" ]
}

@test "parrot_sanitize_target: removes dangerous characters" {
    run parrot_sanitize_target "example.com; rm -rf /"
    [ "$status" -eq 0 ]
    # The function preserves dots, alphanumeric, hyphens, colons, and slashes
    # It should remove semicolons and spaces
    [[ "$output" != *";"* ]]
    [[ "$output" != *" "* ]]
}

@test "parrot_sanitize_target: preserves IP address" {
    run parrot_sanitize_target "192.168.1.1"
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.1" ]
}

# ============================================================================
# MCP MESSAGE VALIDATION TESTS
# ============================================================================

@test "parrot_validate_mcp_message: rejects non-existent file" {
    run parrot_validate_mcp_message "/nonexistent/file.json"
    [ "$status" -eq "$PARROT_ERR_FILE_NOT_FOUND" ]
}

@test "parrot_validate_mcp_message: rejects invalid JSON if jq available" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi
    
    local test_file="$TEST_DIR/invalid.json"
    echo '{"invalid": json}' > "$test_file"
    
    run parrot_validate_mcp_message "$test_file"
    [ "$status" -eq "$PARROT_ERR_INVALID_JSON" ]
}

@test "parrot_validate_mcp_message: rejects missing type field if jq available" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi
    
    local test_file="$TEST_DIR/no_type.json"
    echo '{"content": "test"}' > "$test_file"
    
    run parrot_validate_mcp_message "$test_file"
    [ "$status" -eq "$PARROT_ERR_MISSING_REQUIRED" ]
}

@test "parrot_validate_mcp_message: accepts valid MCP message if jq available" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi
    
    local test_file="$TEST_DIR/valid.json"
    echo '{"type": "mcp_message", "content": "test"}' > "$test_file"
    
    run parrot_validate_mcp_message "$test_file"
    [ "$status" -eq 0 ]
}

# ============================================================================
# COMMAND EXECUTION TESTS
# ============================================================================

@test "parrot_execute_with_timeout: executes successful command" {
    run parrot_execute_with_timeout 5 echo "test"
    [ "$status" -eq 0 ]
    [ "$output" = "test" ]
}

@test "parrot_execute_with_timeout: returns error on failure" {
    run parrot_execute_with_timeout 5 false
    [ "$status" -eq "$PARROT_ERR_TOOL_FAILED" ]
}

@test "parrot_execute_with_timeout: handles timeout if timeout command available" {
    if ! command -v timeout >/dev/null 2>&1; then
        skip "timeout command not available"
    fi
    
    run parrot_execute_with_timeout 1 sleep 10
    [ "$status" -eq "$PARROT_ERR_TOOL_TIMEOUT" ]
}

# ============================================================================
# CIRCUIT BREAKER TESTS
# ============================================================================

@test "parrot_circuit_breaker_check: allows requests when closed" {
    export PARROT_CIRCUIT_BREAKER_DIR="$TEST_DIR/circuit_breaker"
    
    run parrot_circuit_breaker_check "test_service"
    [ "$status" -eq 0 ]
}

@test "parrot_circuit_breaker_success: resets failure count" {
    export PARROT_CIRCUIT_BREAKER_DIR="$TEST_DIR/circuit_breaker"
    mkdir -p "$PARROT_CIRCUIT_BREAKER_DIR"
    
    # Record a success
    parrot_circuit_breaker_success "test_service"
    
    # Check state file
    local state_file="$TEST_DIR/circuit_breaker/test_service.state"
    [ -f "$state_file" ]
    
    local failure_count
    read -r _ failure_count _ < "$state_file"
    [ "$failure_count" -eq 0 ]
}

@test "parrot_circuit_breaker_failure: increments failure count" {
    export PARROT_CIRCUIT_BREAKER_DIR="$TEST_DIR/circuit_breaker"
    
    # Record a failure
    parrot_circuit_breaker_failure "test_service"
    
    # Check state file
    local state_file="$TEST_DIR/circuit_breaker/test_service.state"
    [ -f "$state_file" ]
    
    local failure_count
    read -r _ failure_count _ < "$state_file"
    [ "$failure_count" -eq 1 ]
}

@test "parrot_circuit_breaker_failure: opens circuit after threshold" {
    export PARROT_CIRCUIT_BREAKER_DIR="$TEST_DIR/circuit_breaker"
    export PARROT_CIRCUIT_BREAKER_THRESHOLD=3
    
    # Record multiple failures
    parrot_circuit_breaker_failure "test_service"
    parrot_circuit_breaker_failure "test_service"
    parrot_circuit_breaker_failure "test_service"
    
    # Check state
    local state_file="$TEST_DIR/circuit_breaker/test_service.state"
    local state
    read -r _ _ state < "$state_file"
    [ "$state" = "OPEN" ]
}
