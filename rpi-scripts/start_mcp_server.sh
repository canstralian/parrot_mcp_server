#!/usr/bin/env bash
# =============================================================================
# start_mcp_server.sh - Start the Parrot MCP Server
#
# Description:
#   Starts the Parrot MCP Server with secure IPC communication.
#   This version addresses CRITICAL security vulnerabilities by:
#   - Using secure runtime directory instead of /tmp
#   - Enforcing strict file permissions (600 on IPC files)
#   - Validating all input messages
#   - Implementing proper error handling
#
# Usage:
#   ./start_mcp_server.sh
#
# Security Improvements:
#   - Moved IPC from /tmp to XDG_RUNTIME_DIR or local run/ directory
#   - Added permission checks and validation
#   - Implemented message size limits
#   - Added input sanitization
#
# Exit Codes:
#   0 - Server started successfully
#   1 - Failed to start (configuration, permissions, or runtime error)
# =============================================================================

set -euo pipefail

# Source common configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Initialize secure directories
parrot_init_log_dir || exit 1
parrot_init_ipc_dir || exit 1

# Set current log for this script
PARROT_CURRENT_LOG="$PARROT_SERVER_LOG"

# Check if server is already running
if [ -f "$PARROT_PID_FILE" ]; then
    OLD_PID=$(cat "$PARROT_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        parrot_error "MCP server already running (PID: $OLD_PID)"
        echo "ERROR: MCP server already running with PID $OLD_PID" >&2
        exit 1
    else
        parrot_warn "Stale PID file found, removing"
        rm -f "$PARROT_PID_FILE"
    fi
fi

# Function to handle MCP messages securely
process_mcp_message() {
    local msg_file="$1"
    local msg_type="${2:-unknown}"

    # Validate file exists and is readable
    if [ ! -f "$msg_file" ]; then
        parrot_debug "No $msg_type message file found: $msg_file"
        return 0
    fi

    # Check file size (prevent DoS via large files)
    local file_size
    file_size=$(stat -c '%s' "$msg_file" 2>/dev/null || stat -f '%z' "$msg_file" 2>/dev/null || echo "0")

    if [ "$file_size" -gt "$PARROT_MAX_INPUT_SIZE" ]; then
        parrot_error "Message file too large: $file_size bytes (max: $PARROT_MAX_INPUT_SIZE)"
        return 1
    fi

    # Read and sanitize message content
    local content
    content=$(cat "$msg_file" 2>/dev/null || echo "")
    content=$(parrot_sanitize_input "$content")

    # Process based on message type
    case "$msg_type" in
        valid)
            if echo "$content" | grep -q '"content":"ping"'; then
                parrot_info "MCP message received: ping"
            else
                parrot_warn "MCP message file present but no ping content"
            fi
            ;;
        malformed)
            parrot_error "Malformed MCP message received"
            ;;
        *)
            parrot_debug "Processing message from $msg_file"
            ;;
    esac

    # Securely remove processed message
    if [ "$PARROT_STRICT_PERMS" = "true" ]; then
        shred -u "$msg_file" 2>/dev/null || rm -f "$msg_file"
    else
        rm -f "$msg_file"
    fi
}

# Server main loop function
server_main_loop() {
    parrot_info "MCP server started (PID: $$)"
    parrot_info "IPC directory: $PARROT_IPC_DIR"
    parrot_info "Listening for messages on: $PARROT_MCP_INPUT"

    # In production, this would be a proper event loop with inotify or similar
    # For now, poll periodically (stub implementation with basic message processing)
    local loop_count=0
    local max_loops=5

    while [ $loop_count -lt $max_loops ]; do
        # Process any existing messages
        if [ -f "$PARROT_MCP_INPUT" ] || [ -f "$PARROT_MCP_BAD" ]; then
            process_mcp_message "$PARROT_MCP_INPUT" "valid"
            process_mcp_message "$PARROT_MCP_BAD" "malformed"
        fi

        # Sleep and increment counter
        sleep 1
        loop_count=$((loop_count + 1))
    done

    parrot_debug "Server stub mode loop completed (processed $max_loops iterations)"
    parrot_info "MCP server shutting down normally"
}

# Start server in background and capture PID
(
    # Trap signals for graceful shutdown within the server process
    cleanup_server() {
        local exit_code=$?
        parrot_info "Received shutdown signal, cleaning up..."

        # Remove PID file
        if [ -f "$PARROT_PID_FILE" ]; then
            rm -f "$PARROT_PID_FILE"
        fi

        exit "$exit_code"
    }

    trap cleanup_server INT TERM

    # Run the server main loop
    server_main_loop
) >> "$PARROT_SERVER_LOG" 2>&1 &

# Save PID
SERVER_PID=$!
echo "$SERVER_PID" > "$PARROT_PID_FILE"

# Set secure permissions on PID file
chmod 600 "$PARROT_PID_FILE" 2>/dev/null || true

parrot_info "MCP server started in background (PID: $SERVER_PID)"
echo "MCP server started successfully (PID: $SERVER_PID)"
echo "IPC directory: $PARROT_IPC_DIR"
echo "Log file: $PARROT_SERVER_LOG"

exit 0
