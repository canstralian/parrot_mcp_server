#!/usr/bin/env bash
# process_webhook.sh - Process incoming webhook payloads
# Usage: ./process_webhook.sh <payload_file>

set -euo pipefail

PAYLOAD_FILE="$1"
LOG="./logs/parrot.log"
MSGID=$(date +%s%N)

# Validate JSON payload
if ! jq empty "$PAYLOAD_FILE" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Invalid JSON in webhook payload" >> "$LOG"
    exit 1
fi

# Extract event type if present
EVENT_TYPE=$(jq -r '.type // "unknown"' "$PAYLOAD_FILE")
ACTION=$(jq -r '.action // "unknown"' "$PAYLOAD_FILE")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Processing webhook: type=$EVENT_TYPE, action=$ACTION" >> "$LOG"

# Handle different event types
case "$EVENT_TYPE" in
    "mcp_message")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] MCP message received via webhook" >> "$LOG"
        # Forward to MCP server processing
        METHOD=$(jq -r '.method // "unknown"' "$PAYLOAD_FILE")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] MCP method: $METHOD" >> "$LOG"
        ;;
    
    "github_webhook")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] GitHub webhook: $ACTION" >> "$LOG"
        case "$ACTION" in
            "opened"|"push")
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Triggering health check" >> "$LOG"
                ;;
            *)
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] Unhandled GitHub action: $ACTION" >> "$LOG"
                ;;
        esac
        ;;
    
    "security_alert")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] Security alert received" >> "$LOG"
        SEVERITY=$(jq -r '.severity // "unknown"' "$PAYLOAD_FILE")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] Alert severity: $SEVERITY" >> "$LOG"
        ;;
    
    *)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] [msgid:$MSGID] Unknown webhook type: $EVENT_TYPE" >> "$LOG"
        ;;
esac

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Webhook processing completed" >> "$LOG"
