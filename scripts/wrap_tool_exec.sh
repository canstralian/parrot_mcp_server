#!/usr/bin/env bash
# wrap_tool_exec.sh - Wrapper for tool execution with logging and metrics
# Usage: wrap_tool_exec.sh <tool_name> <user> <target> <command> [args...]
#
# This script:
#   1. Measures tool execution time
#   2. Logs via logging.sh (JSON structured logs)
#   3. Emits Prometheus textfile collector metrics
#
# Metrics written to ${PARROT_METRICS_DIR:-./metrics}/<tool_name>.prom:
#   - tool_executions_total{tool="<name>",status="<success|failure>"} <count>
#   - tool_errors_total{tool="<name>"} <count>
#   - tool_last_duration_ms{tool="<name>"} <milliseconds>
#   - tool_last_execution_timestamp{tool="<name>"} <unix_timestamp>

set -euo pipefail

# Get script directory and source logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/logging.sh
source "${SCRIPT_DIR}/logging.sh"

# Configuration
PARROT_METRICS_DIR="${PARROT_METRICS_DIR:-./metrics}"
mkdir -p "$PARROT_METRICS_DIR"

# Usage check
if [ $# -lt 4 ]; then
    echo "Usage: $0 <tool_name> <user> <target> <command> [args...]" >&2
    echo "Example: $0 backup_home alice /home/alice ./scripts/backup_home.sh" >&2
    exit 2
fi

TOOL_NAME="$1"
USER="$2"
TARGET="$3"
shift 3
COMMAND=("$@")

# Validate tool name (alphanumeric, underscore, dash only)
if ! [[ "$TOOL_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "[ERROR] Invalid tool name: $TOOL_NAME (must be alphanumeric with _ or -)" >&2
    exit 2
fi

# Metrics file for this tool
METRICS_FILE="${PARROT_METRICS_DIR}/${TOOL_NAME}.prom"

# Start timing
START_TIME_MS=$(($(date +%s%N)/1000000))

# Execute command and capture exit code
EXIT_CODE=0
"${COMMAND[@]}" || EXIT_CODE=$?

# End timing
END_TIME_MS=$(($(date +%s%N)/1000000))
DURATION_MS=$((END_TIME_MS - START_TIME_MS))
CURRENT_TIMESTAMP=$(date +%s)

# Determine status
if [ "$EXIT_CODE" -eq 0 ]; then
    STATUS="success"
else
    STATUS="failure"
fi

# Log the execution
log_tool_exec "$TOOL_NAME" "$USER" "$TARGET" "$DURATION_MS" "$EXIT_CODE"

# Update Prometheus metrics
# Read existing metrics if file exists
declare -A EXEC_SUCCESS=()
declare -A EXEC_FAILURE=()
declare -A ERRORS=()

if [ -f "$METRICS_FILE" ]; then
    # Parse existing metrics
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse metric lines: metric_name{labels} value
        if [[ "$line" =~ tool_executions_total\{tool=\"([^\"]+)\",status=\"success\"\}[[:space:]]+([0-9]+) ]]; then
            EXEC_SUCCESS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ tool_executions_total\{tool=\"([^\"]+)\",status=\"failure\"\}[[:space:]]+([0-9]+) ]]; then
            EXEC_FAILURE["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ tool_errors_total\{tool=\"([^\"]+)\"\}[[:space:]]+([0-9]+) ]]; then
            ERRORS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done < "$METRICS_FILE"
fi

# Update counters
if [ "$STATUS" = "success" ]; then
    EXEC_SUCCESS["$TOOL_NAME"]=$((${EXEC_SUCCESS["$TOOL_NAME"]:-0} + 1))
else
    EXEC_FAILURE["$TOOL_NAME"]=$((${EXEC_FAILURE["$TOOL_NAME"]:-0} + 1))
    ERRORS["$TOOL_NAME"]=$((${ERRORS["$TOOL_NAME"]:-0} + 1))
fi

# Write updated metrics file
{
    echo "# HELP tool_executions_total Total number of tool executions"
    echo "# TYPE tool_executions_total counter"
    echo "tool_executions_total{tool=\"${TOOL_NAME}\",status=\"success\"} ${EXEC_SUCCESS["$TOOL_NAME"]:-0}"
    echo "tool_executions_total{tool=\"${TOOL_NAME}\",status=\"failure\"} ${EXEC_FAILURE["$TOOL_NAME"]:-0}"
    echo ""
    echo "# HELP tool_errors_total Total number of tool execution errors"
    echo "# TYPE tool_errors_total counter"
    echo "tool_errors_total{tool=\"${TOOL_NAME}\"} ${ERRORS["$TOOL_NAME"]:-0}"
    echo ""
    echo "# HELP tool_last_duration_ms Duration of last tool execution in milliseconds"
    echo "# TYPE tool_last_duration_ms gauge"
    echo "tool_last_duration_ms{tool=\"${TOOL_NAME}\"} ${DURATION_MS}"
    echo ""
    echo "# HELP tool_last_execution_timestamp Unix timestamp of last tool execution"
    echo "# TYPE tool_last_execution_timestamp gauge"
    echo "tool_last_execution_timestamp{tool=\"${TOOL_NAME}\"} ${CURRENT_TIMESTAMP}"
} > "$METRICS_FILE"

# Exit with the same code as the wrapped command
exit "$EXIT_CODE"
