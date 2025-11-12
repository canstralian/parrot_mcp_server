#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message and simulates a running server with improved error handling

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Check if server is already running
if [ -f "$PARROT_PID_FILE" ] && kill -0 "$(cat "$PARROT_PID_FILE" 2>/dev/null)" 2>/dev/null; then
    parrot_error "MCP server is already running (PID: $(cat "$PARROT_PID_FILE"))"
    exit 1
fi

# Start the server process
{
    parrot_info "MCP server starting..."

    # Simulate handling a valid MCP message
    if [ -f "$PARROT_MCP_INPUT" ]; then
        if parrot_validate_json "$PARROT_MCP_INPUT"; then
            if parrot_command_exists "jq"; then
                if jq -e '.content == "ping"' "$PARROT_MCP_INPUT" >/dev/null 2>&1; then
                    parrot_info "MCP message received: ping"
                else
                    parrot_warn "MCP message file present but no ping content"
                fi
            else
                # Fallback for when jq is not installed
                if grep -q '"content":"ping"' "$PARROT_MCP_INPUT" 2>/dev/null; then
                    parrot_info "MCP message received: ping"
                else
                    parrot_warn "MCP message file present but no ping content"
                fi
            fi
        else
            parrot_error "Invalid JSON in MCP input file"
        fi
    else
        parrot_debug "No MCP input file found at: $PARROT_MCP_INPUT"
    fi

    # Simulate handling a malformed MCP message
    if [ -f "$PARROT_MCP_BAD" ]; then
        parrot_error "Malformed MCP message received"
    fi

    parrot_info "MCP server started successfully"

    # Keep process alive for test harness
    sleep 5
} &

# Save PID
SERVER_PID=$!
echo "$SERVER_PID" > "$PARROT_PID_FILE"

parrot_info "MCP server started with PID: $SERVER_PID"
