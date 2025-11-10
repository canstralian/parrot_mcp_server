#!/usr/bin/env bash
# notify_slack.sh - Send notifications to Slack webhook
# Usage: ./notify_slack.sh <message> [channel]
# Requires: SLACK_WEBHOOK_URL environment variable

set -euo pipefail

MESSAGE="$1"
CHANNEL="${2:-}"
LOG="./logs/parrot.log"
MSGID=$(date +%s%N)

mkdir -p ./logs

# Check for webhook URL
if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] SLACK_WEBHOOK_URL not set" >> "$LOG"
    echo "Error: SLACK_WEBHOOK_URL environment variable not set" >&2
    exit 1
fi

# Build JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg msg "$MESSAGE" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{text: $msg, timestamp: $ts}')

# Add channel if specified
if [ -n "$CHANNEL" ]; then
    JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq --arg ch "$CHANNEL" '. + {channel: $ch}')
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Sending Slack notification" >> "$LOG"

# Send to Slack
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/slack_response.txt \
    -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

if [ "$HTTP_CODE" = "200" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Slack notification sent successfully" >> "$LOG"
    rm -f /tmp/slack_response.txt
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Slack notification failed: HTTP $HTTP_CODE" >> "$LOG"
    cat /tmp/slack_response.txt >> "$LOG" 2>/dev/null || true
    rm -f /tmp/slack_response.txt
    exit 1
fi
