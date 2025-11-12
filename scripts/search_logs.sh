#!/usr/bin/env bash
# search_logs.sh - Grep-based JSON log search utility
# Usage: search_logs.sh [options]
#
# Options:
#   --tool=<name>        Filter by tool name
#   --user=<name>        Filter by user
#   --status=<status>    Filter by status (success|failure)
#   --level=<level>      Filter by log level (INFO|ERROR|WARN|DEBUG)
#   --since=<date>       Filter logs since date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)
#   --tail=<n>           Show last n lines (default: all)
#   --help               Show this help message
#
# Examples:
#   search_logs.sh --tool=backup_home --status=failure
#   search_logs.sh --user=alice --since=2024-01-01
#   search_logs.sh --level=ERROR --tail=50

set -euo pipefail

# Default log file
PARROT_LOG_FILE="${PARROT_LOG_FILE:-./logs/parrot.log}"

# Show help
show_help() {
    cat << 'EOF'
Usage: search_logs.sh [options]

Search JSON-formatted logs with grep-based filtering.

Options:
  --tool=<name>        Filter by tool name
  --user=<name>        Filter by user
  --status=<status>    Filter by status (success|failure)
  --level=<level>      Filter by log level (INFO|ERROR|WARN|DEBUG)
  --since=<date>       Filter logs since date (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)
  --tail=<n>           Show last n lines (default: all)
  --help               Show this help message

Examples:
  search_logs.sh --tool=backup_home --status=failure
  search_logs.sh --user=alice --since=2024-01-01
  search_logs.sh --level=ERROR --tail=50
  search_logs.sh --tool=health_check --since=2024-01-15T10:00:00

Output:
  Matching log entries in JSON format, one per line.

EOF
}

# Parse arguments
TOOL_FILTER=""
USER_FILTER=""
STATUS_FILTER=""
LEVEL_FILTER=""
SINCE_FILTER=""
TAIL_LINES=""

for arg in "$@"; do
    case "$arg" in
        --tool=*)
            TOOL_FILTER="${arg#*=}"
            ;;
        --user=*)
            USER_FILTER="${arg#*=}"
            ;;
        --status=*)
            STATUS_FILTER="${arg#*=}"
            ;;
        --level=*)
            LEVEL_FILTER="${arg#*=}"
            ;;
        --since=*)
            SINCE_FILTER="${arg#*=}"
            ;;
        --tail=*)
            TAIL_LINES="${arg#*=}"
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $arg" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Check if log file exists
if [ ! -f "$PARROT_LOG_FILE" ]; then
    echo "[ERROR] Log file not found: $PARROT_LOG_FILE" >&2
    exit 1
fi

# Build grep pipeline
GREP_CMD="cat \"$PARROT_LOG_FILE\""

# Apply tool filter
if [ -n "$TOOL_FILTER" ]; then
    GREP_CMD="$GREP_CMD | grep '\"tool\":\"${TOOL_FILTER}\"'"
fi

# Apply user filter
if [ -n "$USER_FILTER" ]; then
    GREP_CMD="$GREP_CMD | grep '\"user\":\"${USER_FILTER}\"'"
fi

# Apply status filter
if [ -n "$STATUS_FILTER" ]; then
    GREP_CMD="$GREP_CMD | grep '\"status\":\"${STATUS_FILTER}\"'"
fi

# Apply level filter
if [ -n "$LEVEL_FILTER" ]; then
    GREP_CMD="$GREP_CMD | grep '\"level\":\"${LEVEL_FILTER}\"'"
fi

# Apply since filter
if [ -n "$SINCE_FILTER" ]; then
    # Convert date to comparable format (basic ISO 8601 comparison works lexically)
    # Normalize date format if needed (YYYY-MM-DD -> YYYY-MM-DDT00:00:00)
    if [[ "$SINCE_FILTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        SINCE_FILTER="${SINCE_FILTER}T00:00:00"
    fi
    
    # Grep for timestamps >= since filter
    # We'll use awk for more precise timestamp comparison
    GREP_CMD="$GREP_CMD | awk -F'\"timestamp\":\"' '\$2 >= \"${SINCE_FILTER}\"'"
fi

# Apply tail filter
if [ -n "$TAIL_LINES" ]; then
    GREP_CMD="$GREP_CMD | tail -n ${TAIL_LINES}"
fi

# Execute the pipeline
eval "$GREP_CMD"
