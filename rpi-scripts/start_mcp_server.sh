#!/usr/bin/env bash
# Start the Parrot MCP Server
# Handles MCP protocol messages with comprehensive error handling and validation

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration and error handling
# shellcheck source=common_config.sh disable=SC1091
source "${SCRIPT_DIR}/common_config.sh"
# shellcheck source=error_handling.sh disable=SC1091
source "${SCRIPT_DIR}/error_handling.sh"

# Initialize
parrot_init_log_dir
PARROT_CURRENT_LOG="$PARROT_SERVER_LOG"
REQUEST_ID=$(parrot_generate_request_id "server")

# Process MCP message with error handling
process_mcp_message() {
    local msg_file="$1"
    local req_id
    req_id=$(parrot_generate_request_id)
    
    parrot_info "Processing MCP message from: $msg_file [request_id:$req_id]"
    
    # Validate message
    if ! parrot_validate_mcp_message "$msg_file"; then
        local error_response
        error_response=$(parrot_format_error_response \
            "$PARROT_ERR_MALFORMED_MESSAGE" \
            "MCP message validation failed" \
            "message" \
            "$msg_file" \
            "valid JSON with required fields" \
            "$req_id")
        
        parrot_error "Message validation failed [request_id:$req_id]"
        echo "$error_response" >> "${PARROT_LOG_DIR}/error_responses.log"
        return "$PARROT_ERR_MALFORMED_MESSAGE"
    fi
    
    # Extract message type if jq is available
    if command -v jq >/dev/null 2>&1; then
        local msg_type
        msg_type=$(jq -r '.type // "unknown"' "$msg_file" 2>/dev/null || echo "unknown")
        
        local msg_content
        msg_content=$(jq -r '.content // ""' "$msg_file" 2>/dev/null || echo "")
        
        parrot_info "Message type: $msg_type, content: $msg_content [request_id:$req_id]"
        
        # Handle different message types
        case "$msg_type" in
            mcp_message)
                if [ "$msg_content" = "ping" ]; then
                    parrot_info "Received ping, sending pong [request_id:$req_id]"
                    echo "{\"type\":\"mcp_response\",\"content\":\"pong\",\"request_id\":\"$req_id\"}" \
                        > "${PARROT_IPC_DIR}/mcp_out_${req_id}.json"
                else
                    parrot_warn "Unknown message content: $msg_content [request_id:$req_id]"
                fi
                ;;
            *)
                local error_response
                error_response=$(parrot_format_error_response \
                    "$PARROT_ERR_INVALID_MESSAGE_TYPE" \
                    "Unknown message type: $msg_type" \
                    "type" \
                    "$msg_type" \
                    "mcp_message" \
                    "$req_id")
                
                parrot_error "Unknown message type: $msg_type [request_id:$req_id]"
                echo "$error_response" >> "${PARROT_LOG_DIR}/error_responses.log"
                return "$PARROT_ERR_INVALID_MESSAGE_TYPE"
                ;;
        esac
    else
        # Fallback: simple grep-based parsing
        if grep -q '"content":"ping"' "$msg_file" 2>/dev/null; then
            parrot_info "Received ping (fallback parsing) [request_id:$req_id]"
        else
            parrot_warn "Message file present but content unclear (jq not available) [request_id:$req_id]"
        fi
    fi
    
    return 0
}

# Main server loop
run_server() {
    parrot_info "MCP server starting [request_id:$REQUEST_ID]"
    
    # Check for existing messages
    if [ -f "$PARROT_MCP_INPUT" ]; then
        if process_mcp_message "$PARROT_MCP_INPUT"; then
            parrot_info "Successfully processed message [request_id:$REQUEST_ID]"
        else
            parrot_error "Failed to process message [request_id:$REQUEST_ID]"
        fi
    fi
    
    # Check for bad messages
    if [ -f "$PARROT_MCP_BAD" ]; then
        local req_id
        req_id=$(parrot_generate_request_id)
        
        local error_response
        error_response=$(parrot_format_error_response \
            "$PARROT_ERR_MALFORMED_MESSAGE" \
            "Malformed MCP message detected" \
            "message" \
            "$PARROT_MCP_BAD" \
            "valid JSON structure" \
            "$req_id")
        
        parrot_error "Malformed message detected [request_id:$req_id]"
        echo "$error_response" >> "${PARROT_LOG_DIR}/error_responses.log"
    fi
    
    # Keep server alive for testing
    parrot_info "Server running, will exit after 5 seconds [request_id:$REQUEST_ID]"
    sleep 5
    
    parrot_info "Server shutting down [request_id:$REQUEST_ID]"
}

# Run in background
{
    run_server
} >> "$PARROT_CURRENT_LOG" 2>&1 &

echo $! > "$PARROT_PID_FILE"
parrot_debug "Server PID: $(cat "$PARROT_PID_FILE")"
