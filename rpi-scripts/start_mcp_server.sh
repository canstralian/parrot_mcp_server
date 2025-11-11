#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling
# Uses secure named pipes for IPC instead of /tmp files

set -euo pipefail

# Load common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Cleanup function to remove named pipes on exit
cleanup() {
    parrot_info "Shutting down MCP server, cleaning up pipes..."
    parrot_cleanup_pipes "$PARROT_MCP_INPUT_PIPE" "$PARROT_MCP_OUTPUT_PIPE"
}

# Set up trap to cleanup on exit
trap cleanup EXIT INT TERM

# Initialize IPC directory and create named pipes
parrot_init_ipc_dir || exit 1
parrot_create_pipe "$PARROT_MCP_INPUT_PIPE" || exit 1
parrot_create_pipe "$PARROT_MCP_OUTPUT_PIPE" || exit 1

parrot_info "MCP server started (stub) - listening on pipes"
parrot_debug "Input pipe: $PARROT_MCP_INPUT_PIPE"
parrot_debug "Output pipe: $PARROT_MCP_OUTPUT_PIPE"

# Background process to handle messages
{
    while true; do
        # Read from input pipe (blocks until data available)
        if read -r message < "$PARROT_MCP_INPUT_PIPE"; then
            # Sanitize the message
            message=$(parrot_sanitize_input "$message")
            
            # Check for ping message
            if echo "$message" | grep -q '"content":"ping"'; then
                parrot_info "MCP message received: ping"
                echo '{"type":"mcp_response","content":"pong"}' > "$PARROT_MCP_OUTPUT_PIPE"
            elif echo "$message" | grep -q '"type":"mcp_message"'; then
                parrot_info "Valid MCP message received"
                echo '{"type":"mcp_response","status":"ok"}' > "$PARROT_MCP_OUTPUT_PIPE"
            else
                parrot_error "Malformed MCP message received"
                # Write to bad message file for tracking
                echo "$message" > "$PARROT_MCP_BAD"
            fi
        fi
    done
} &

SERVER_PID=$!
echo "$SERVER_PID" > "$PARROT_PID_FILE"

# Keep main process alive
wait "$SERVER_PID"
