#!/usr/bin/env bash
# daily_workflow.sh - Robust daily maintenance workflow
# Author: Canstralian
# Description: Runs a sequence of maintenance tasks with error handling and logging
# Usage: ./daily_workflow.sh

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Set script-specific log file
PARROT_CURRENT_LOG="$PARROT_WORKFLOW_LOG"

log() {
    parrot_info "$*"
}

error_exit() {
    parrot_error "$1"
    parrot_send_notification "Daily Workflow Error" "Daily workflow failed: $1"
    exit 1
}

run_task() {
    local task="$1"
    local max_retries="${2:-$PARROT_RETRY_COUNT}"
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        log "Running $task (attempt $((retry_count + 1))/$max_retries)"

        if "${SCRIPT_DIR}/cli.sh" "$task"; then
            log "$task completed successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                local delay=$((PARROT_RETRY_DELAY * retry_count))
                parrot_warn "$task failed (attempt $retry_count/$max_retries), retrying in ${delay}s..."
                sleep "$delay"
            fi
        fi
    done

    error_exit "$task failed after $max_retries attempts"
}

log "Starting daily maintenance workflow"

# Check disk usage first
run_task "check_disk ${PARROT_DISK_THRESHOLD}"

# Clean cache
run_task "clean_cache"

# System update (less critical, allow failure)
if [ "$PARROT_AUTO_UPDATE" = "true" ]; then
    if "${SCRIPT_DIR}/cli.sh" system_update; then
        log "System update completed"
    else
        parrot_warn "System update failed, but continuing workflow"
    fi
else
    log "System auto-update disabled (PARROT_AUTO_UPDATE=false)"
fi

# Backup home directory
if [ -d "$PARROT_BACKUP_DIR" ] || mkdir -p "$PARROT_BACKUP_DIR" 2>/dev/null; then
    run_task "backup_home ${PARROT_BACKUP_DIR}"
else
    parrot_warn "Backup directory not accessible: $PARROT_BACKUP_DIR, skipping backup"
fi

# Rotate logs
run_task "log_rotate"

log "Daily maintenance workflow completed successfully"

parrot_send_notification "Daily Workflow Success" "Daily workflow completed successfully"