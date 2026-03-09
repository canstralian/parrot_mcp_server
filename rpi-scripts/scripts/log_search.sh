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

# Build jq filter using --arg to pass user-supplied values safely, preventing
# jq injection via crafted --level/--user/--status/--tool/--since/--until values.
output_results() {
    local temp_file
    temp_file=$(mktemp)

    # Assemble jq --arg flags and a safe filter expression
    local jq_args=()
    local jq_conditions=()

    # SC2016: single-quoted strings are intentional jq expressions where $var = jq --arg variables
    # shellcheck disable=SC2016
    if [ -n "$FILTER_LEVEL" ]; then
        jq_args+=(--arg filter_level "$FILTER_LEVEL")
        jq_conditions+=('(.level == $filter_level)')
    fi

    # shellcheck disable=SC2016
    if [ -n "$FILTER_TOOL" ]; then
        jq_args+=(--arg filter_tool "$FILTER_TOOL")
        jq_conditions+=('(.tool == $filter_tool or .operation == $filter_tool)')
    fi

    # shellcheck disable=SC2016
    if [ -n "$FILTER_USER" ]; then
        jq_args+=(--arg filter_user "$FILTER_USER")
        jq_conditions+=('(.user == $filter_user or .audit_user == $filter_user)')
    fi

    # shellcheck disable=SC2016
    if [ -n "$FILTER_STATUS" ]; then
        jq_args+=(--arg filter_status "$FILTER_STATUS")
        jq_conditions+=('(.status == $filter_status or .audit_result == $filter_status)')
    fi

    # shellcheck disable=SC2016
    if [ -n "$FILTER_SINCE" ]; then
        local since_iso
        since_iso=$(date -d "$FILTER_SINCE" -u '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "$FILTER_SINCE")
        jq_args+=(--arg filter_since "$since_iso")
        jq_conditions+=('(.timestamp >= $filter_since)')
    fi

    # shellcheck disable=SC2016
    if [ -n "$FILTER_UNTIL" ]; then
        local until_iso
        until_iso=$(date -d "$FILTER_UNTIL" -u '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "$FILTER_UNTIL")
        jq_args+=(--arg filter_until "$until_iso")
        jq_conditions+=('(.timestamp <= $filter_until)')
    fi

    # Combine conditions with 'and'; if none, select everything
    local jq_filter="."
    if [ "${#jq_conditions[@]}" -gt 0 ]; then
        # Join array elements with ' and ' using printf for portability
        local combined
        combined=$(printf '%s and ' "${jq_conditions[@]}")
        combined="${combined% and }"  # strip trailing ' and '
        jq_filter="select($combined)"
    fi

    # Filter logs with jq using safe arg passing
    jq -c "${jq_args[@]}" "$jq_filter" "$LOG_FILE" 2>/dev/null >"$temp_file" || {
        rm -f "$temp_file"
        parrot_error "Error filtering logs."
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
            # Output as CSV with a fixed schema matching the selected fields
            # Only emit a header and rows if there is at least one matching entry
            if [ -s "$temp_file" ]; then
                echo "timestamp,level,message,user,operation,status,duration_ms"
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
