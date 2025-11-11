#!/usr/bin/env bash
# Start the Parrot MCP Server (minimal stub)
# Logs a startup message, simulates message handling and stays in the foreground

set -euo pipefail

mkdir -p ./logs
LOG=./logs/parrot.log
PIDFILE=./logs/mcp_server.pid
touch "$LOG"

log() {
        local level=$1
        shift
        printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >>"$LOG"
}

simulate_messages() {
        local msgid
        msgid=$(date +%s%N)
        log "INFO" "[msgid:$msgid] MCP server started (stub)"

        if [ -f /tmp/mcp_in.json ]; then
                if grep -q '"content":"ping"' /tmp/mcp_in.json; then
                        log "INFO" "[msgid:$msgid] MCP message received: ping"
                else
                        log "WARN" "[msgid:$msgid] MCP message file present but no ping content"
                fi
        else
                log "WARN" "[msgid:$msgid] No valid MCP message file found"
        fi

        if [ -f /tmp/mcp_bad.json ]; then
                log "ERROR" "[msgid:$msgid] Malformed MCP message received"
        fi
}

cleanup() {
        log "INFO" "Shutting down MCP server stub"
        rm -f "$PIDFILE"
        exit 0
}

echo $$ >"$PIDFILE"
trap cleanup SIGINT SIGTERM

simulate_messages

while true; do
        sleep 60 &
        wait $!
done
