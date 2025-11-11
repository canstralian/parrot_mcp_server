#!/usr/bin/env bash
# health_check.sh - System health monitoring and workflow validation
# Author: Canstralian
# Description: Checks system health and validates recent workflow executions
# Usage: ./health_check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

parrot_realpath() {
    local target="$1"

    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$target" 2>/dev/null
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$target" <<'PY' 2>/dev/null
import os
import sys
if len(sys.argv) != 2:
    raise SystemExit(1)
print(os.path.realpath(sys.argv[1]))
PY
        return
    fi

    if command -v python >/dev/null 2>&1; then
        python - "$target" <<'PY' 2>/dev/null
import os
import sys
if len(sys.argv) != 2:
    raise SystemExit(1)
print(os.path.realpath(sys.argv[1]))
PY
        return
    fi

    return 1
}

PARROT_BASE_DIR="${PARROT_BASE_DIR:-$(parrot_realpath "$SCRIPT_DIR/.." || echo "$SCRIPT_DIR/..")}"
PARROT_LOG_DIR="${PARROT_LOG_DIR:-$PARROT_BASE_DIR/logs}"
PARROT_WORKFLOW_LOG="${PARROT_WORKFLOW_LOG:-$PARROT_LOG_DIR/daily_workflow.log}"
LOG_FILE="${LOG_FILE:-$PARROT_LOG_DIR/health_check.log}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH_CHECK] $*" | tee -a "$LOG_FILE"
}

alert() {
    log "ALERT: $1"
    if [ -n "$ALERT_EMAIL" ]; then
        echo "Health Check Alert: $1" | mail -s "System Health Alert" "$ALERT_EMAIL"
    fi
}

parrot_path_within_base() {
    local candidate="$1"
    local base="$2"

    case "$candidate" in
        "")
            return 1
            ;;
    esac

    local resolved_base
    resolved_base=$(parrot_realpath "$base") || return 1

    case "$candidate" in
        "$resolved_base"|"$resolved_base"/*)
            return 0
            ;;
    esac

    return 1
}

parrot_resolve_path() {
    local candidate="$1"

    if [[ -z "$candidate" ]]; then
        return 1
    fi

    if [[ "$candidate" = /* ]]; then
        parrot_realpath "$candidate"
    else
        parrot_realpath "$PARROT_BASE_DIR/$candidate"
    fi
}

parrot_get_valid_path() {
    local candidate="$1"
    local resolved

    resolved=$(parrot_resolve_path "$candidate") || return 1

    if ! parrot_path_within_base "$resolved" "$PARROT_BASE_DIR"; then
        return 1
    fi

    printf '%s\n' "$resolved"
}

# Check disk usage
check_disk() {
    local threshold=90
    local usage

    usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$usage" -gt "$threshold" ]; then
        alert "Disk usage is ${usage}%, above ${threshold}% threshold"
    else
        log "Disk usage: ${usage}% (OK)"
    fi
}

# Check recent workflow logs
check_workflows() {
    local workflow_log="$PARROT_WORKFLOW_LOG"
    local resolved_workflow_log

    if ! resolved_workflow_log=$(parrot_get_valid_path "$workflow_log"); then
        alert "Invalid workflow log path: $workflow_log"
        return 1
    fi

    if [ -f "$resolved_workflow_log" ]; then
        local last_run
        last_run=$(tail -1 "$resolved_workflow_log" | cut -d' ' -f1-2)
        local last_timestamp
        last_timestamp=$(date -d "$last_run" +%s 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local hours_since=$(((now - last_timestamp) / 3600))

        if [ "$hours_since" -gt 25 ]; then  # Allow 1 hour grace
            alert "Daily workflow hasn't run in ${hours_since} hours"
        else
            log "Daily workflow last ran: $last_run"
        fi
    else
        alert "Workflow log file not found: $resolved_workflow_log"
    fi
}

# Check system load
check_load() {
    local load
    load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
    local load_int
    load_int=$(echo "$load * 100" | bc -l | cut -d. -f1)
    if [ "$load_int" -gt 200 ]; then  # Load > 2.00
        alert "System load is high: $load"
    else
        log "System load: $load (OK)"
    fi
}

# Check MCP server status
check_mcp_server() {
    if pgrep -f "start_mcp_server.sh" >/dev/null; then
        log "MCP server is running"
    else
        alert "MCP server is not running"
    fi
}

log "Starting health check"

check_disk
check_workflows
check_load
check_mcp_server

log "Health check completed"

