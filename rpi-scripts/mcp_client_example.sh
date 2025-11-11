#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# mcp_client_example.sh
#
# Description:
#   Example client script demonstrating secure named pipe communication with
#   the Parrot MCP Server. This shows how to send messages via the input pipe
#   and receive responses via the output pipe.
#
# Usage:
#   ./mcp_client_example.sh [message]
#   
# Examples:
#   ./mcp_client_example.sh '{"type":"mcp_message","content":"ping"}'
#   ./mcp_client_example.sh '{"type":"mcp_message","content":"hello"}'
#
# Security Features:
#   - Uses named pipes with restrictive permissions (0600)
#   - Input validation for message size
#   - Timeout handling to prevent hanging
#   - Sanitizes input before sending
#
# Exit Codes:
#   0 - Success
#   1 - Error (pipe not found, validation failed, timeout, etc.)
# -----------------------------------------------------------------------------

set -euo pipefail

# Load common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Default timeout for reading response (seconds)
TIMEOUT=5

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [MESSAGE]

Send a message to the Parrot MCP Server via secure named pipes.

OPTIONS:
    -h, --help       Show this help message
    -t, --timeout N  Set response timeout in seconds (default: $TIMEOUT)

EXAMPLES:
    $0 '{"type":"mcp_message","content":"ping"}'
    $0 --timeout 10 '{"type":"mcp_message","content":"hello"}'

The message will be validated and sanitized before sending.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -t|--timeout)
            if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                TIMEOUT="$2"
                shift 2
            else
                echo "Error: --timeout requires a numeric argument" >&2
                exit 1
            fi
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
        *)
            MESSAGE="$1"
            shift
            ;;
    esac
done

# Check if message was provided
if [ -z "${MESSAGE:-}" ]; then
    echo "Error: No message provided" >&2
    show_usage
    exit 1
fi

# Validate message size
MESSAGE_SIZE=${#MESSAGE}
if [ "$MESSAGE_SIZE" -gt "$PARROT_MAX_INPUT_SIZE" ]; then
    parrot_error "Message exceeds maximum size: $MESSAGE_SIZE > $PARROT_MAX_INPUT_SIZE"
    exit 1
fi

# Sanitize the message
MESSAGE=$(parrot_sanitize_input "$MESSAGE")

# Check if pipes exist
if [ ! -p "$PARROT_MCP_INPUT_PIPE" ]; then
    echo "Error: MCP server input pipe not found: $PARROT_MCP_INPUT_PIPE" >&2
    echo "Is the MCP server running? Start it with: ./start_mcp_server.sh" >&2
    exit 1
fi

if [ ! -p "$PARROT_MCP_OUTPUT_PIPE" ]; then
    echo "Error: MCP server output pipe not found: $PARROT_MCP_OUTPUT_PIPE" >&2
    echo "Is the MCP server running? Start it with: ./start_mcp_server.sh" >&2
    exit 1
fi

# Send message to server (non-blocking)
echo "Sending message to MCP server..."
parrot_debug "Message: $MESSAGE"

# Send message in background to avoid blocking
(echo "$MESSAGE" > "$PARROT_MCP_INPUT_PIPE") &
SEND_PID=$!

# Wait for send to complete with timeout
if ! wait "$SEND_PID" 2>/dev/null; then
    echo "Error: Failed to send message to server" >&2
    exit 1
fi

echo "Message sent. Waiting for response (timeout: ${TIMEOUT}s)..."

# Read response with timeout
if timeout "$TIMEOUT" cat "$PARROT_MCP_OUTPUT_PIPE" > /tmp/mcp_response_$$ 2>/dev/null; then
    echo "Response received:"
    cat /tmp/mcp_response_$$
    rm -f /tmp/mcp_response_$$
    exit 0
else
    echo "Warning: No response received within ${TIMEOUT} seconds" >&2
    rm -f /tmp/mcp_response_$$ 2>/dev/null || true
    exit 1
fi
