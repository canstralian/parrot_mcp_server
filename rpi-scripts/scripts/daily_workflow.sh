#!/usr/bin/env bash
# daily_workflow.sh - Robust daily maintenance workflow
# Author: Canstralian
# Description: Runs a sequence of maintenance tasks with error handling and logging
# Usage: ./daily_workflow.sh

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")/.."
LOG_FILE="./logs/daily_workflow.log"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"  # Optional email for notifications

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DAILY_WORKFLOW] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    if [ -n "$NOTIFY_EMAIL" ]; then
        echo "Daily workflow failed: $1" | mail -s "Daily Workflow Error" "$NOTIFY_EMAIL"
    fi
    exit 1
}

run_task() {
    local task="$1"
    local max_retries="${2:-3}"
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        log "Running $task (attempt $((retry_count + 1)))"
        if "$SCRIPT_DIR/cli.sh" "$task"; then
            log "$task completed successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "$task failed (attempt $retry_count), retrying in 60 seconds..."
            sleep 60
        fi
    done

    error_exit "$task failed after $max_retries attempts"
}

log "Starting daily maintenance workflow"

# Check disk usage first
run_task "check_disk 90"

# Clean cache
run_task "clean_cache"

# System update (less critical, allow failure)
if "$SCRIPT_DIR/cli.sh" system_update >> "$LOG_FILE" 2>&1; then
    log "System update completed"
else
    log "WARNING: System update failed, but continuing workflow"
fi

# Backup home directory
run_task "backup_home /var/backups"

# Rotate logs
run_task "log_rotate"

log "Daily maintenance workflow completed successfully"

if [ -n "$NOTIFY_EMAIL" ]; then
    echo "Daily workflow completed successfully" | mail -s "Daily Workflow Success" "$NOTIFY_EMAIL"
fi