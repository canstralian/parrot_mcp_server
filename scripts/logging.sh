#!/usr/bin/env bash
# logging.sh - Structured JSON logging functions for Parrot MCP Server
# Usage: source scripts/logging.sh
#
# Provides:
#   - log_json: emit structured JSON log entries
#   - log_tool_exec: specialized logging for tool executions
#   - sanitize_value: redact sensitive keys (password/token/secret/key)
#
# All logs are written to ${PARROT_LOG_FILE:-./logs/parrot.log}

set -euo pipefail

# Default log file location
PARROT_LOG_FILE="${PARROT_LOG_FILE:-./logs/parrot.log}"

# Ensure log directory exists
mkdir -p "$(dirname "$PARROT_LOG_FILE")"

# sanitize_value: redact sensitive fields
# Usage: sanitize_value "key" "value"
# Returns: "[REDACTED]" if key matches sensitive patterns, else returns value
sanitize_value() {
    local key="$1"
    local value="$2"
    
    # Convert key to lowercase for case-insensitive matching
    local key_lower
    key_lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    
    # Check if key contains sensitive patterns
    # Match: password, token, secret, api_key, auth tokens, but not generic *_key fields
    if echo "$key_lower" | grep -qE '(password|passwd|pwd|token|secret|^api_key$|^apikey$|^key$|auth_token|authorization)'; then
        echo "[REDACTED]"
    else
        echo "$value"
    fi
}

# escape_json: escape special characters for JSON strings
# Usage: escape_json "string with \"quotes\" and \n newlines"
escape_json() {
    local str="$1"
    # Escape backslashes first, then quotes, then newlines/tabs
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    echo "$str"
}

# log_json: emit a structured JSON log entry
# Usage: log_json level message [key1=val1 key2=val2 ...]
# Example: log_json INFO "User logged in" user=alice action=login
log_json() {
    local level="${1:-INFO}"
    local message="${2:-}"
    shift 2 || true
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "unknown")
    
    # Start JSON object
    local json="{\"timestamp\":\"$timestamp\""
    json="${json},\"level\":\"$level\""
    json="${json},\"hostname\":\"$hostname\""
    
    # Escape message
    local escaped_message
    escaped_message=$(escape_json "$message")
    json="${json},\"message\":\"$escaped_message\""
    
    # Add optional key=value pairs
    while [ $# -gt 0 ]; do
        local kv="$1"
        shift
        
        # Parse key=value
        if [[ "$kv" == *"="* ]]; then
            local key="${kv%%=*}"
            local value="${kv#*=}"
            
            # Sanitize sensitive values
            value=$(sanitize_value "$key" "$value")
            
            # Escape value
            local escaped_value
            escaped_value=$(escape_json "$value")
            
            # Add to JSON
            json="${json},\"${key}\":\"${escaped_value}\""
        fi
    done
    
    # Close JSON object and append to log file
    json="${json}}"
    echo "$json" >> "$PARROT_LOG_FILE"
}

# log_tool_exec: specialized logging for tool executions
# Usage: log_tool_exec tool user target duration_ms exit_code [extra_key=val ...]
# Example: log_tool_exec backup_home alice /home/alice 1234 0 size=100MB
log_tool_exec() {
    if [ $# -lt 5 ]; then
        echo "[ERROR] log_tool_exec requires at least 5 arguments: tool user target duration_ms exit_code" >&2
        return 1
    fi
    
    local tool="$1"
    local user="$2"
    local target="$3"
    local duration_ms="$4"
    local exit_code="$5"
    shift 5
    
    # Determine status from exit code
    local status="success"
    if [ "$exit_code" -ne 0 ]; then
        status="failure"
    fi
    
    # Build message
    local message="Tool execution: $tool"
    
    # Call log_json with structured fields
    log_json "INFO" "$message" \
        "event_type=tool_execution" \
        "tool=$tool" \
        "user=$user" \
        "target=$target" \
        "duration_ms=$duration_ms" \
        "exit_code=$exit_code" \
        "status=$status" \
        "$@"
}

# log_error: convenience function for error logging
# Usage: log_error "error message" [key=val ...]
log_error() {
    log_json "ERROR" "$@"
}

# log_info: convenience function for info logging
# Usage: log_info "info message" [key=val ...]
log_info() {
    log_json "INFO" "$@"
}

# log_warn: convenience function for warning logging
# Usage: log_warn "warning message" [key=val ...]
log_warn() {
    log_json "WARN" "$@"
}

# log_debug: convenience function for debug logging
# Usage: log_debug "debug message" [key=val ...]
log_debug() {
    if [ "${PARROT_LOG_LEVEL:-INFO}" = "DEBUG" ]; then
        log_json "DEBUG" "$@"
    fi
}
