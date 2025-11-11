#!/usr/bin/env bash
# health_check.sh - System health monitoring and workflow validation
# Author: Canstralian
# Description: Checks system health and validates recent workflow executions
# Usage: ./health_check.sh [--disk-threshold PERCENT] [--load-threshold FLOAT]

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Set script-specific log file
PARROT_CURRENT_LOG="$PARROT_HEALTH_LOG"

# Parse command-line arguments with validation
DISK_THRESHOLD="$PARROT_DISK_THRESHOLD"
LOAD_THRESHOLD="$PARROT_LOAD_THRESHOLD"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk-threshold)
            if [ -z "${2:-}" ]; then
                parrot_error "Missing value for --disk-threshold"
                exit 1
            fi
            if ! parrot_validate_percentage "$2"; then
                parrot_error "Invalid disk threshold: $2 (must be 0-100)"
                exit 1
            fi
            DISK_THRESHOLD="$2"
            shift 2
            ;;
        --load-threshold)
            if [ -z "${2:-}" ]; then
                parrot_error "Missing value for --load-threshold"
                exit 1
            fi
            LOAD_THRESHOLD="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --disk-threshold PERCENT  Disk usage threshold (0-100, default: $PARROT_DISK_THRESHOLD)"
            echo "  --load-threshold FLOAT    Load average threshold (default: $PARROT_LOAD_THRESHOLD)"
            echo "  --help, -h                Show this help message"
            echo ""
            echo "Environment variables (from config.env):"
            echo "  PARROT_ALERT_EMAIL        Email for alerts (currently: ${PARROT_ALERT_EMAIL:-not set})"
            echo "  PARROT_DISK_THRESHOLD     Default disk threshold"
            echo "  PARROT_LOAD_THRESHOLD     Default load threshold"
            exit 0
            ;;
        *)
            parrot_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

log() {
    parrot_info "$*"
}

alert() {
    parrot_warn "ALERT: $1"
    parrot_send_notification "System Health Alert" "$1"
}

# Check disk usage
check_disk() {
    local usage
    if ! usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//'); then
        parrot_error "Failed to check disk usage"
        return 1
    fi

    if ! parrot_validate_number "$usage"; then
        parrot_error "Invalid disk usage value: $usage"
        return 1
    fi

    if [ "$usage" -gt "$DISK_THRESHOLD" ]; then
        alert "Disk usage is ${usage}%, above ${DISK_THRESHOLD}% threshold"
    else
        log "Disk usage: ${usage}% (OK)"
    fi
}

# Check recent workflow logs
check_workflows() {
    local workflow_log="$PARROT_WORKFLOW_LOG"

    if ! parrot_validate_path "$workflow_log"; then
        parrot_error "Invalid workflow log path: $workflow_log"
        return 1
    fi

    if [ -f "$workflow_log" ]; then
        local last_run
        last_run=$(tail -1 "$workflow_log" 2>/dev/null | cut -d' ' -f1-2)

        if [ -z "$last_run" ]; then
            parrot_warn "Workflow log is empty: $workflow_log"
            return 0
        fi

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
    if ! load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs); then
        parrot_error "Failed to check system load"
        return 1
    fi

    # Convert load threshold to integer for comparison
    local threshold_int
    if parrot_command_exists "bc"; then
        threshold_int=$(echo "$LOAD_THRESHOLD * 100" | bc -l | cut -d. -f1)
        local load_int
        load_int=$(echo "$load * 100" | bc -l | cut -d. -f1 2>/dev/null || echo 0)

        if [ "$load_int" -gt "$threshold_int" ]; then
            alert "System load is high: $load (threshold: $LOAD_THRESHOLD)"
        else
            log "System load: $load (OK)"
        fi
    else
        parrot_warn "bc not available, skipping precise load comparison"
        log "System load: $load (threshold: $LOAD_THRESHOLD - comparison skipped)"
    fi
}

# Check MCP server status
check_mcp_server() {
    if pgrep -f "start_mcp_server.sh" >/dev/null 2>&1; then
        log "MCP server is running"
    else
        alert "MCP server is not running"
    fi
}

# Main execution
main() {
    log "Starting health check"
    log "Configuration: disk_threshold=${DISK_THRESHOLD}%, load_threshold=${LOAD_THRESHOLD}"

    local exit_code=0

    # Run all checks, tracking failures
    if ! check_disk; then
        parrot_error "Disk check failed"
        exit_code=1
    fi

    if ! check_workflows; then
        parrot_error "Workflow check failed"
        exit_code=1
    fi

    if ! check_load; then
        parrot_error "Load check failed"
        exit_code=1
    fi

    if ! check_mcp_server; then
        parrot_error "MCP server check failed"
        exit_code=1
    fi

    if [ "$exit_code" -eq 0 ]; then
        log "Health check completed successfully"
    else
        log "Health check completed with errors"
    fi

    return "$exit_code"
}

# Run main function
main