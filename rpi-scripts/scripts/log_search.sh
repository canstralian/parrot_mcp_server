#!/usr/bin/env bash
# log_search.sh - Search and filter logs with multiple criteria
# Usage: ./log_search.sh [options]
# Options:
#   --level LEVEL       Filter by log level (DEBUG, INFO, WARN, ERROR, CRITICAL)
#   --tool TOOL         Filter by tool name
#   --user USER         Filter by username
#   --status STATUS     Filter by status (success, error, etc.)
#   --since DATE        Filter logs since date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
#   --until DATE        Filter logs until date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
#   --format FORMAT     Output format: text (default), json, csv
#   --file LOGFILE      Log file to search (default: parrot.json.log)
#   --output FILE       Output to file instead of stdout

set -euo pipefail

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Default values
FILTER_LEVEL=""
FILTER_TOOL=""
FILTER_USER=""
FILTER_STATUS=""
FILTER_SINCE=""
FILTER_UNTIL=""
OUTPUT_FORMAT="text"
LOG_FILE="${PARROT_JSON_LOG}"
OUTPUT_FILE=""

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --level)
            FILTER_LEVEL="$2"
            shift 2
            ;;
        --tool)
            FILTER_TOOL="$2"
            shift 2
            ;;
        --user)
            FILTER_USER="$2"
            shift 2
            ;;
        --status)
            FILTER_STATUS="$2"
            shift 2
            ;;
        --since)
            FILTER_SINCE="$2"
            shift 2
            ;;
        --until)
            FILTER_UNTIL="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --file)
            LOG_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Search and filter logs with multiple criteria.

Options:
  --level LEVEL       Filter by log level (DEBUG, INFO, WARN, ERROR, CRITICAL)
  --tool TOOL         Filter by tool name
  --user USER         Filter by username
  --status STATUS     Filter by status (success, error, etc.)
  --since DATE        Filter logs since date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
  --until DATE        Filter logs until date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
  --format FORMAT     Output format: text (default), json, csv
  --file LOGFILE      Log file to search (default: parrot.json.log)
  --output FILE       Output to file instead of stdout
  --help, -h          Show this help message

Examples:
  # Search for all ERROR logs
  $0 --level ERROR

  # Search for logs from specific user since yesterday
  $0 --user admin --since "$(date -d yesterday '+%Y-%m-%d')"

  # Export logs as CSV
  $0 --format csv --output logs.csv

  # Search for tool executions with errors
  $0 --tool nmap --status error --format json
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    parrot_error "Log file not found: $LOG_FILE"
    exit 1
fi

# Build jq filter based on criteria
JQ_FILTER="."

if [ -n "$FILTER_LEVEL" ]; then
    JQ_FILTER="$JQ_FILTER | select(.level == \"$FILTER_LEVEL\")"
fi

if [ -n "$FILTER_TOOL" ]; then
    JQ_FILTER="$JQ_FILTER | select(.tool == \"$FILTER_TOOL\" or .operation == \"$FILTER_TOOL\")"
fi

if [ -n "$FILTER_USER" ]; then
    JQ_FILTER="$JQ_FILTER | select(.user == \"$FILTER_USER\" or .audit_user == \"$FILTER_USER\")"
fi

if [ -n "$FILTER_STATUS" ]; then
    JQ_FILTER="$JQ_FILTER | select(.status == \"$FILTER_STATUS\" or .audit_result == \"$FILTER_STATUS\")"
fi

if [ -n "$FILTER_SINCE" ]; then
    # Convert date to ISO format if needed
    SINCE_ISO=$(date -d "$FILTER_SINCE" -u '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "$FILTER_SINCE")
    JQ_FILTER="$JQ_FILTER | select(.timestamp >= \"$SINCE_ISO\")"
fi

if [ -n "$FILTER_UNTIL" ]; then
    # Convert date to ISO format if needed
    UNTIL_ISO=$(date -d "$FILTER_UNTIL" -u '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "$FILTER_UNTIL")
    JQ_FILTER="$JQ_FILTER | select(.timestamp <= \"$UNTIL_ISO\")"
fi

# Function to output results
output_results() {
    local temp_file
    temp_file=$(mktemp)

    # Filter logs with jq
    jq -c "$JQ_FILTER" "$LOG_FILE" 2>/dev/null >"$temp_file" || {
        rm -f "$temp_file"
        parrot_error "Error filtering logs. Check jq filter syntax."
        exit 1
    }

    # Format output based on requested format
    case "$OUTPUT_FORMAT" in
        json)
            # Output as JSON array
            echo "["
            local first=true
            while IFS= read -r line; do
                if [ "$first" = true ]; then
                    first=false
                else
                    echo ","
                fi
                echo "  $line"
            done <"$temp_file"
            echo "]"
            ;;
        csv)
            # Output as CSV
            # Extract all unique keys first
            local keys
            keys=$(jq -r 'keys | @csv' "$temp_file" 2>/dev/null | head -1)
            if [ -n "$keys" ]; then
                echo "$keys"
                jq -r '[.timestamp, .level, .message, .user // "", .operation // "", .status // "", .duration_ms // ""] | @csv' "$temp_file" 2>/dev/null
            fi
            ;;
        text|*)
            # Output as readable text
            jq -r '[.timestamp, .level, .user // "", .message] | @tsv' "$temp_file" 2>/dev/null | \
                awk -F'\t' '{printf "[%s] [%-8s] [%-12s] %s\n", $1, $2, $3, $4}'
            ;;
    esac

    rm -f "$temp_file"
}

# Execute search and output
if [ -n "$OUTPUT_FILE" ]; then
    output_results >"$OUTPUT_FILE"
    parrot_info "Results written to: $OUTPUT_FILE"
else
    output_results
fi

# Log the search operation
parrot_audit_log "log_search" "log_file=$LOG_FILE" "success" \
    "filters=level:$FILTER_LEVEL,tool:$FILTER_TOOL,user:$FILTER_USER,status:$FILTER_STATUS"
