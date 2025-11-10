#!/usr/bin/env bash
# api_client.sh - Generic REST API client helper
# Usage: ./api_client.sh <method> <url> [data] [headers]

set -euo pipefail

METHOD="${1:-GET}"
URL="$2"
DATA="${3:-}"
HEADERS="${4:-Content-Type: application/json}"
LOG="./logs/parrot.log"
MSGID=$(date +%s%N)

mkdir -p ./logs

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] API request: $METHOD $URL" >> "$LOG"

# Build curl command
CURL_CMD="curl -s -X $METHOD"

# Add headers
if [ -n "$HEADERS" ]; then
    while IFS=';' read -ra HEADER_ARRAY; do
        for header in "${HEADER_ARRAY[@]}"; do
            CURL_CMD="$CURL_CMD -H \"$header\""
        done
    done <<< "$HEADERS"
fi

# Add data for POST/PUT/PATCH
if [ -n "$DATA" ] && [[ "$METHOD" =~ ^(POST|PUT|PATCH)$ ]]; then
    CURL_CMD="$CURL_CMD -d '$DATA'"
fi

# Add URL
CURL_CMD="$CURL_CMD '$URL'"

# Execute request
RESPONSE_FILE="/tmp/api_response_${MSGID}.json"
HTTP_CODE=$(eval "$CURL_CMD -w '%{http_code}' -o '$RESPONSE_FILE'")

# Log response
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] API response: HTTP $HTTP_CODE" >> "$LOG"

# Check response status
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] API request successful" >> "$LOG"
    cat "$RESPONSE_FILE"
    rm -f "$RESPONSE_FILE"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] API request failed with HTTP $HTTP_CODE" >> "$LOG"
    if [ -f "$RESPONSE_FILE" ]; then
        cat "$RESPONSE_FILE" >> "$LOG"
        cat "$RESPONSE_FILE" >&2
        rm -f "$RESPONSE_FILE"
    fi
    exit 1
fi
