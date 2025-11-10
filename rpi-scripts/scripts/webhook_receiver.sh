#!/usr/bin/env bash
# webhook_receiver.sh - Simple webhook receiver for MCP server
# Listens for incoming HTTP POST requests and processes webhook payloads
# Usage: ./webhook_receiver.sh [port] [handler_script]

set -euo pipefail

PORT="${1:-8080}"
HANDLER="${2:-./scripts/process_webhook.sh}"
LOG="./logs/parrot.log"
MSGID=$(date +%s%N)

mkdir -p ./logs

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Webhook receiver starting on port $PORT" >> "$LOG"

# Check if handler script exists
if [ ! -f "$HANDLER" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Handler script not found: $HANDLER" >> "$LOG"
    exit 1
fi

# Function to extract JSON body from HTTP request
extract_body() {
    # Read until we find the blank line separating headers from body
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [ -z "$line" ] && break
    done
    # Read the rest as body
    cat
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Webhook receiver ready. Waiting for requests..." >> "$LOG"

# Simple webhook receiver using netcat
# Note: This is a minimal implementation for demonstration
# For production, consider using a proper HTTP server
while true; do
    TIMESTAMP=$(date +%s%N)
    PAYLOAD_FILE="/tmp/webhook_${TIMESTAMP}.json"
    
    {
        # Receive HTTP request
        extract_body > "$PAYLOAD_FILE"
        
        # Send HTTP response
        echo "HTTP/1.1 200 OK"
        echo "Content-Type: application/json"
        echo "Connection: close"
        echo ""
        TIMESTAMP_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        echo "{\"status\":\"received\",\"timestamp\":\"$TIMESTAMP_ISO\"}"
    } | nc -l -p "$PORT" -q 1
    
    # Process webhook if payload received
    if [ -s "$PAYLOAD_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$TIMESTAMP] Webhook received, processing..." >> "$LOG"
        
        # Execute handler script
        if bash "$HANDLER" "$PAYLOAD_FILE" >> "$LOG" 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$TIMESTAMP] Webhook processed successfully" >> "$LOG"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$TIMESTAMP] Webhook processing failed" >> "$LOG"
        fi
        
        # Cleanup
        rm -f "$PAYLOAD_FILE"
    fi
    
    # Small delay to prevent CPU spinning
    sleep 0.1
done
