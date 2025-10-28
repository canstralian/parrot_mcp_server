#!/usr/bin/env bash
# health_check.sh - System health monitoring and workflow validation
# Author: Canstralian
# Description: Checks system health and validates recent workflow executions
# Usage: ./health_check.sh

set -euo pipefail

LOG_FILE="./logs/health_check.log"
ALERT_EMAIL="${ALERT_EMAIL:-}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH_CHECK] $*" | tee -a "$LOG_FILE"
}

alert() {
    log "ALERT: $1"
    if [ -n "$ALERT_EMAIL" ]; then
        echo "Health Check Alert: $1" | mail -s "System Health Alert" "$ALERT_EMAIL"
    fi
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
    local workflow_log="./logs/daily_workflow.log"
    if [ -f "$workflow_log" ]; then
        local last_run
        last_run=$(tail -1 "$workflow_log" | cut -d' ' -f1-2)
        local last_timestamp
        last_timestamp=$(date -d "$last_run" +%s 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local hours_since=$(( (now - last_timestamp) / 3600 ))

        if [ "$hours_since" -gt 25 ]; then  # Allow 1 hour grace
            alert "Daily workflow hasn't run in ${hours_since} hours"
        else
            log "Daily workflow last ran: $last_run"
        fi
    else
        alert "Workflow log file not found: $workflow_log"
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