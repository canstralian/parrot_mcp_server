#!/usr/bin/env bash
# error_handling.sh - Error handling utilities for Parrot MCP Server
# Provides standardized error responses, error codes, and exception handling
# Usage: source "$(dirname "$0")/error_handling.sh" at the top of your script

set -euo pipefail

# ============================================================================
# ERROR CODES - Standardized error code constants
# ============================================================================

# Success
readonly PARROT_ERR_SUCCESS=0

# Validation Errors (10-19)
readonly PARROT_ERR_INVALID_INPUT=10
readonly PARROT_ERR_INVALID_JSON=11
readonly PARROT_ERR_INVALID_TARGET=12
readonly PARROT_ERR_INVALID_PORT=13
readonly PARROT_ERR_INVALID_PARAMETER=14
readonly PARROT_ERR_MISSING_REQUIRED=15

# Tool Execution Errors (20-29)
readonly PARROT_ERR_TOOL_FAILED=20
readonly PARROT_ERR_TOOL_NOT_FOUND=21
readonly PARROT_ERR_TOOL_TIMEOUT=22
readonly PARROT_ERR_TOOL_PERMISSION=23

# System Errors (30-39)
readonly PARROT_ERR_FILE_NOT_FOUND=30
readonly PARROT_ERR_PERMISSION_DENIED=31
readonly PARROT_ERR_DISK_FULL=32
readonly PARROT_ERR_OUT_OF_MEMORY=33

# Protocol Errors (40-49)
readonly PARROT_ERR_PROTOCOL_VIOLATION=40
readonly PARROT_ERR_MESSAGE_TOO_LARGE=41
readonly PARROT_ERR_INVALID_MESSAGE_TYPE=42
readonly PARROT_ERR_MALFORMED_MESSAGE=43

# Authentication/Authorization Errors (50-59)
readonly PARROT_ERR_AUTH_FAILED=50
readonly PARROT_ERR_AUTH_REQUIRED=51
readonly PARROT_ERR_INSUFFICIENT_PERMS=52

# Network/Communication Errors (60-69)
readonly PARROT_ERR_NETWORK_TIMEOUT=60
readonly PARROT_ERR_CONNECTION_FAILED=61
readonly PARROT_ERR_HOST_UNREACHABLE=62

# General Errors (90-99)
readonly PARROT_ERR_UNKNOWN=90
readonly PARROT_ERR_INTERNAL=91
readonly PARROT_ERR_NOT_IMPLEMENTED=92

# ============================================================================
# ERROR CODE MAPPING - Human-readable error names
# ============================================================================

parrot_error_code_to_name() {
    local code="$1"
    case "$code" in
        0) echo "SUCCESS" ;;
        10) echo "INVALID_INPUT" ;;
        11) echo "INVALID_JSON" ;;
        12) echo "INVALID_TARGET" ;;
        13) echo "INVALID_PORT" ;;
        14) echo "INVALID_PARAMETER" ;;
        15) echo "MISSING_REQUIRED" ;;
        20) echo "TOOL_FAILED" ;;
        21) echo "TOOL_NOT_FOUND" ;;
        22) echo "TOOL_TIMEOUT" ;;
        23) echo "TOOL_PERMISSION" ;;
        30) echo "FILE_NOT_FOUND" ;;
        31) echo "PERMISSION_DENIED" ;;
        32) echo "DISK_FULL" ;;
        33) echo "OUT_OF_MEMORY" ;;
        40) echo "PROTOCOL_VIOLATION" ;;
        41) echo "MESSAGE_TOO_LARGE" ;;
        42) echo "INVALID_MESSAGE_TYPE" ;;
        43) echo "MALFORMED_MESSAGE" ;;
        50) echo "AUTH_FAILED" ;;
        51) echo "AUTH_REQUIRED" ;;
        52) echo "INSUFFICIENT_PERMS" ;;
        60) echo "NETWORK_TIMEOUT" ;;
        61) echo "CONNECTION_FAILED" ;;
        62) echo "HOST_UNREACHABLE" ;;
        90) echo "UNKNOWN" ;;
        91) echo "INTERNAL" ;;
        92) echo "NOT_IMPLEMENTED" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# ============================================================================
# REQUEST ID GENERATION
# ============================================================================

# Generate a unique request ID
# Usage: parrot_generate_request_id [PREFIX]
# shellcheck disable=SC2120
parrot_generate_request_id() {
    local prefix="${1:-req}"
    echo "${prefix}_$(date +%s)_$$_${RANDOM}"
}

# ============================================================================
# ERROR RESPONSE FORMATTING
# ============================================================================

# Format a standardized error response in JSON
# Usage: parrot_format_error_response CODE MESSAGE [FIELD] [PROVIDED] [EXPECTED] [REQUEST_ID]
parrot_format_error_response() {
    local code="$1"
    local message="$2"
    local field="${3:-}"
    local provided="${4:-null}"
    local expected="${5:-}"
    # shellcheck disable=SC2119
    local request_id="${6:-$(parrot_generate_request_id)}"
    
    local error_name
    error_name="$(parrot_error_code_to_name "$code")"
    
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    
    # Build details object
    local details="{}"
    if [ -n "$field" ]; then
        details="{\"field\":\"$field\""
        if [ "$provided" != "null" ]; then
            details="$details,\"provided\":\"$provided\""
        else
            details="$details,\"provided\":null"
        fi
        if [ -n "$expected" ]; then
            details="$details,\"expected\":\"$expected\""
        fi
        details="$details}"
    fi
    
    # Build error response
    cat <<EOF
{
  "error": {
    "code": "$error_name",
    "exit_code": $code,
    "message": "$message",
    "details": $details,
    "request_id": "$request_id",
    "timestamp": "$timestamp"
  }
}
EOF
}

# ============================================================================
# ERROR HANDLING UTILITIES
# ============================================================================

# Handle an error and log it
# Usage: parrot_handle_error CODE MESSAGE [EXTRA_CONTEXT]
parrot_handle_error() {
    local code="$1"
    local message="$2"
    local context="${3:-}"
    
    # Source common_config if not already loaded
    if ! declare -F parrot_error >/dev/null 2>&1; then
        # shellcheck source=common_config.sh disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/common_config.sh" 2>/dev/null || true
    fi
    
    local error_name
    error_name="$(parrot_error_code_to_name "$code")"
    
    if [ -n "$context" ]; then
        if declare -F parrot_error >/dev/null 2>&1; then
            parrot_error "[$error_name] $message | Context: $context"
        else
            echo "ERROR: [$error_name] $message | Context: $context" >&2
        fi
    else
        if declare -F parrot_error >/dev/null 2>&1; then
            parrot_error "[$error_name] $message"
        else
            echo "ERROR: [$error_name] $message" >&2
        fi
    fi
}

# Wrap command execution with error handling and retry logic
# Usage: parrot_execute_with_retry COMMAND [ARGS...]
parrot_execute_with_retry() {
    local cmd=("$@")
    
    # Try to use common_config retry if available
    if declare -F parrot_retry >/dev/null 2>&1; then
        if parrot_retry "${cmd[@]}"; then
            return 0
        else
            return $PARROT_ERR_TOOL_FAILED
        fi
    else
        # Fallback: simple retry logic
        local max_attempts=3
        local attempt=1
        local delay=5
        
        while [ "$attempt" -le "$max_attempts" ]; do
            if "${cmd[@]}"; then
                return 0
            fi
            
            if [ "$attempt" -lt "$max_attempts" ]; then
                sleep "$delay"
                delay=$((delay * 2))
            fi
            
            attempt=$((attempt + 1))
        done
        
        return $PARROT_ERR_TOOL_FAILED
    fi
}

# Execute command with timeout
# Usage: parrot_execute_with_timeout TIMEOUT_SECONDS COMMAND [ARGS...]
parrot_execute_with_timeout() {
    local timeout="$1"
    shift
    local cmd=("$@")
    
    # Use timeout command if available
    if command -v timeout >/dev/null 2>&1; then
        if timeout "$timeout" "${cmd[@]}"; then
            return 0
        else
            local exit_code=$?
            if [ "$exit_code" -eq 124 ]; then
                return $PARROT_ERR_TOOL_TIMEOUT
            else
                return $PARROT_ERR_TOOL_FAILED
            fi
        fi
    else
        # Fallback: no timeout support
        if "${cmd[@]}"; then
            return 0
        else
            return $PARROT_ERR_TOOL_FAILED
        fi
    fi
}

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

# Validate IP address (IPv4)
parrot_validate_ipv4() {
    local ip="$1"
    
    # Check format: four octets separated by dots
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # Validate each octet is 0-255
    local IFS='.'
    local -a octets
    read -ra octets <<< "$ip"
    
    for octet in "${octets[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done
    
    return 0
}

# Validate hostname
parrot_validate_hostname() {
    local hostname="$1"
    
    # RFC 1123 hostname validation
    # - Maximum 253 characters
    # - Labels separated by dots
    # - Each label: 1-63 characters, alphanumeric and hyphens
    # - Labels cannot start or end with hyphen
    
    if [ ${#hostname} -gt 253 ]; then
        return 1
    fi
    
    if [[ ! "$hostname" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    
    return 0
}

# Validate port number
parrot_validate_port() {
    local port="$1"
    
    # Check if it's a number
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check range (1-65535)
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    
    return 0
}

# Validate port range (e.g., "80", "80-443", "22,80,443")
parrot_validate_port_range() {
    local port_spec="$1"
    
    # Split by comma
    local IFS=','
    local -a port_parts
    read -ra port_parts <<< "$port_spec"
    
    for part in "${port_parts[@]}"; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Range format
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            
            if ! parrot_validate_port "$start" || ! parrot_validate_port "$end"; then
                return 1
            fi
            
            if [ "$start" -gt "$end" ]; then
                return 1
            fi
        else
            # Single port
            if ! parrot_validate_port "$part"; then
                return 1
            fi
        fi
    done
    
    return 0
}

# Validate target (IP or hostname)
parrot_validate_target() {
    local target="$1"
    
    # Try IP validation first
    if parrot_validate_ipv4 "$target"; then
        return 0
    fi
    
    # Try hostname validation
    if parrot_validate_hostname "$target"; then
        return 0
    fi
    
    return 1
}

# Sanitize target for safe command execution (prevent command injection)
parrot_sanitize_target() {
    local target="$1"
    
    # Remove any characters that could be used for command injection
    # Only allow: alphanumeric, dots, hyphens, colons (for IPv6)
    echo "$target" | tr -cd '[:alnum:].:/-'
}

# ============================================================================
# MCP MESSAGE VALIDATION
# ============================================================================

# Validate MCP message structure
# Usage: parrot_validate_mcp_message FILE
parrot_validate_mcp_message() {
    local msg_file="$1"
    
    # Check if file exists
    if [ ! -f "$msg_file" ]; then
        parrot_handle_error "$PARROT_ERR_FILE_NOT_FOUND" "Message file not found: $msg_file"
        return $PARROT_ERR_FILE_NOT_FOUND
    fi
    
    # Check file size
    local max_size="${PARROT_MAX_INPUT_SIZE:-1048576}"
    local size
    size=$(stat -c%s "$msg_file" 2>/dev/null || stat -f%z "$msg_file" 2>/dev/null || echo 0)
    
    if [ "$size" -gt "$max_size" ]; then
        parrot_handle_error "$PARROT_ERR_MESSAGE_TOO_LARGE" "Message size $size exceeds maximum $max_size bytes"
        return $PARROT_ERR_MESSAGE_TOO_LARGE
    fi
    
    # Validate JSON syntax if jq is available
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty "$msg_file" >/dev/null 2>&1; then
            parrot_handle_error "$PARROT_ERR_INVALID_JSON" "Invalid JSON syntax in message file"
            return $PARROT_ERR_INVALID_JSON
        fi
        
        # Check required fields
        if ! jq -e '.type' "$msg_file" >/dev/null 2>&1; then
            parrot_handle_error "$PARROT_ERR_MISSING_REQUIRED" "Missing required field: type"
            return $PARROT_ERR_MISSING_REQUIRED
        fi
    fi
    
    return 0
}

# ============================================================================
# ERROR RECOVERY
# ============================================================================

# Create error recovery point
parrot_create_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_dir="${PARROT_CHECKPOINT_DIR:-/tmp/parrot_checkpoints}"
    
    mkdir -p "$checkpoint_dir"
    
    local checkpoint_file="$checkpoint_dir/${checkpoint_name}.checkpoint"
    
    # Save current state
    {
        echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "pwd=$(pwd)"
        echo "user=$(whoami)"
        env | grep '^PARROT_' || true
    } > "$checkpoint_file"
    
    echo "$checkpoint_file"
}

# Rollback to checkpoint (stub - implement based on specific needs)
parrot_rollback_checkpoint() {
    local checkpoint_file="$1"
    
    if [ ! -f "$checkpoint_file" ]; then
        parrot_handle_error "$PARROT_ERR_FILE_NOT_FOUND" "Checkpoint file not found: $checkpoint_file"
        return 1
    fi
    
    # Load checkpoint state
    # shellcheck disable=SC1090
    source "$checkpoint_file"
    
    parrot_info "Rolled back to checkpoint: $checkpoint_file"
    return 0
}

# ============================================================================
# CIRCUIT BREAKER PATTERN
# ============================================================================

# Simple circuit breaker state management
# State file format: <timestamp> <failure_count> <state>
# States: CLOSED (normal), OPEN (failing), HALF_OPEN (testing)

parrot_circuit_breaker_check() {
    local service_name="$1"
    local state_dir="${PARROT_CIRCUIT_BREAKER_DIR:-/tmp/parrot_circuit_breaker}"
    local state_file="$state_dir/${service_name}.state"
    
    mkdir -p "$state_dir"
    
    # Default state
    local failure_count=0
    local state="CLOSED"
    local last_failure=0
    
    # Read existing state
    if [ -f "$state_file" ]; then
        read -r last_failure failure_count state < "$state_file"
    fi
    
    local now
    now=$(date +%s)
    local threshold_failures="${PARROT_CIRCUIT_BREAKER_THRESHOLD:-5}"
    local timeout_seconds="${PARROT_CIRCUIT_BREAKER_TIMEOUT:-60}"
    
    case "$state" in
        CLOSED)
            # Normal operation
            return 0
            ;;
        OPEN)
            # Check if timeout has elapsed
            local elapsed=$((now - last_failure))
            if [ "$elapsed" -ge "$timeout_seconds" ]; then
                # Try half-open
                echo "$now $failure_count HALF_OPEN" > "$state_file"
                return 0
            else
                # Still open, reject
                return 1
            fi
            ;;
        HALF_OPEN)
            # Allow one attempt
            return 0
            ;;
    esac
}

parrot_circuit_breaker_success() {
    local service_name="$1"
    local state_dir="${PARROT_CIRCUIT_BREAKER_DIR:-/tmp/parrot_circuit_breaker}"
    local state_file="$state_dir/${service_name}.state"
    
    # Reset to closed state
    echo "$(date +%s) 0 CLOSED" > "$state_file"
}

parrot_circuit_breaker_failure() {
    local service_name="$1"
    local state_dir="${PARROT_CIRCUIT_BREAKER_DIR:-/tmp/parrot_circuit_breaker}"
    local state_file="$state_dir/${service_name}.state"
    
    mkdir -p "$state_dir"
    
    local failure_count=0
    local state="CLOSED"
    
    # Read existing state
    if [ -f "$state_file" ]; then
        read -r _ failure_count state < "$state_file"
    fi
    
    failure_count=$((failure_count + 1))
    local threshold_failures="${PARROT_CIRCUIT_BREAKER_THRESHOLD:-5}"
    
    if [ "$failure_count" -ge "$threshold_failures" ]; then
        state="OPEN"
    fi
    
    echo "$(date +%s) $failure_count $state" > "$state_file"
}

# ============================================================================
# EXPORTS
# ============================================================================

# Export error codes for use in other scripts
export PARROT_ERR_SUCCESS PARROT_ERR_INVALID_INPUT PARROT_ERR_INVALID_JSON
export PARROT_ERR_INVALID_TARGET PARROT_ERR_INVALID_PORT PARROT_ERR_INVALID_PARAMETER
export PARROT_ERR_MISSING_REQUIRED PARROT_ERR_TOOL_FAILED PARROT_ERR_TOOL_NOT_FOUND
export PARROT_ERR_TOOL_TIMEOUT PARROT_ERR_TOOL_PERMISSION PARROT_ERR_FILE_NOT_FOUND
export PARROT_ERR_PERMISSION_DENIED PARROT_ERR_DISK_FULL PARROT_ERR_OUT_OF_MEMORY
export PARROT_ERR_PROTOCOL_VIOLATION PARROT_ERR_MESSAGE_TOO_LARGE
export PARROT_ERR_INVALID_MESSAGE_TYPE PARROT_ERR_MALFORMED_MESSAGE
export PARROT_ERR_AUTH_FAILED PARROT_ERR_AUTH_REQUIRED PARROT_ERR_INSUFFICIENT_PERMS
export PARROT_ERR_NETWORK_TIMEOUT PARROT_ERR_CONNECTION_FAILED
export PARROT_ERR_HOST_UNREACHABLE PARROT_ERR_UNKNOWN PARROT_ERR_INTERNAL
export PARROT_ERR_NOT_IMPLEMENTED
