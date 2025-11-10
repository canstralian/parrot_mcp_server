#!/usr/bin/env bash
# mcp_jsonrpc.sh - JSON-RPC 2.0 message handler for MCP protocol
# Usage: ./mcp_jsonrpc.sh <input_file> <output_file>

set -euo pipefail

INPUT_FILE="$1"
OUTPUT_FILE="$2"
LOG="./logs/parrot.log"
MSGID=$(date +%s%N)

mkdir -p ./logs

# Validate input JSON
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Invalid JSON input" >> "$LOG"
    
    # Return JSON-RPC error
    jq -n \
        --arg id "null" \
        '{jsonrpc: "2.0", id: $id, error: {code: -32700, message: "Parse error"}}' \
        > "$OUTPUT_FILE"
    exit 1
fi

# Extract JSON-RPC fields
JSONRPC_VERSION=$(jq -r '.jsonrpc // "unknown"' "$INPUT_FILE")
REQUEST_ID=$(jq -r '.id // null' "$INPUT_FILE")
METHOD=$(jq -r '.method // "unknown"' "$INPUT_FILE")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] JSON-RPC request: method=$METHOD, id=$REQUEST_ID" >> "$LOG"

# Validate JSON-RPC version
if [ "$JSONRPC_VERSION" != "2.0" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Invalid JSON-RPC version: $JSONRPC_VERSION" >> "$LOG"
    
    jq -n \
        --arg id "$REQUEST_ID" \
        '{jsonrpc: "2.0", id: $id, error: {code: -32600, message: "Invalid Request"}}' \
        > "$OUTPUT_FILE"
    exit 1
fi

# Route to appropriate handler based on method
case "$METHOD" in
    "tools/call")
        TOOL_NAME=$(jq -r '.params.name // "unknown"' "$INPUT_FILE")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Calling tool: $TOOL_NAME" >> "$LOG"
        
        # Execute tool (example)
        case "$TOOL_NAME" in
            "health_check")
                RESULT=$(bash ./scripts/health_check.sh 2>&1 || echo "Health check failed")
                jq -n \
                    --arg id "$REQUEST_ID" \
                    --arg text "$RESULT" \
                    '{jsonrpc: "2.0", id: $id, result: {content: [{type: "text", text: $text}]}}' \
                    > "$OUTPUT_FILE"
                ;;
            
            "check_disk")
                RESULT=$(bash ./scripts/check_disk.sh 2>&1 || echo "Disk check failed")
                jq -n \
                    --arg id "$REQUEST_ID" \
                    --arg text "$RESULT" \
                    '{jsonrpc: "2.0", id: $id, result: {content: [{type: "text", text: $text}]}}' \
                    > "$OUTPUT_FILE"
                ;;
            
            *)
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Unknown tool: $TOOL_NAME" >> "$LOG"
                jq -n \
                    --arg id "$REQUEST_ID" \
                    --arg tool "$TOOL_NAME" \
                    '{jsonrpc: "2.0", id: $id, error: {code: -32601, message: "Method not found", data: {tool: $tool}}}' \
                    > "$OUTPUT_FILE"
                exit 1
                ;;
        esac
        ;;
    
    "ping")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] Ping received" >> "$LOG"
        jq -n \
            --arg id "$REQUEST_ID" \
            '{jsonrpc: "2.0", id: $id, result: "pong"}' \
            > "$OUTPUT_FILE"
        ;;
    
    *)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$MSGID] Unknown method: $METHOD" >> "$LOG"
        jq -n \
            --arg id "$REQUEST_ID" \
            --arg method "$METHOD" \
            '{jsonrpc: "2.0", id: $id, error: {code: -32601, message: "Method not found", data: {method: $method}}}' \
            > "$OUTPUT_FILE"
        exit 1
        ;;
esac

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [msgid:$MSGID] JSON-RPC request processed successfully" >> "$LOG"
