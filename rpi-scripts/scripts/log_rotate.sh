#!/usr/bin/env bash
# log_rotate.sh - Enhanced log rotation with size and age limits
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-11-12
# Description: Rotates and compresses log files based on size and age
# Usage: ./log_rotate.sh [--size SIZE] [--age DAYS] [--count NUM]

set -euo pipefail

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Default values from config or defaults
MAX_SIZE_MB=100
MAX_AGE_DAYS="${PARROT_LOG_MAX_AGE:-30}"
MAX_COUNT="${PARROT_LOG_ROTATION_COUNT:-5}"

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --size)
            MAX_SIZE_MB="$2"
            shift 2
            ;;
        --age)
            MAX_AGE_DAYS="$2"
            shift 2
            ;;
        --count)
            MAX_COUNT="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Rotate and compress log files based on size and age.

Options:
  --size SIZE    Maximum log file size in MB (default: 100)
  --age DAYS     Maximum log file age in days (default: 30)
  --count NUM    Maximum number of rotated logs to keep (default: 5)
  --help, -h     Show this help message

Examples:
  # Rotate logs larger than 50MB
  $0 --size 50

  # Keep logs for 60 days
  $0 --age 60

  # Keep only 3 rotated versions
  $0 --count 3
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

parrot_info "Starting log rotation (size: ${MAX_SIZE_MB}MB, age: ${MAX_AGE_DAYS}d, count: $MAX_COUNT)"

# Convert MB to bytes for comparison
# Use awk for floating point support
MAX_SIZE_BYTES=$(awk "BEGIN {printf \"%.0f\", $MAX_SIZE_MB * 1024 * 1024}")

# Function to rotate a single log file
rotate_log_file() {
    local logfile="$1"
    
    if [ ! -f "$logfile" ]; then
        return
    fi

    # Get file size
    local size
    size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo 0)

    # Check if rotation is needed
    if [ "$size" -ge "$MAX_SIZE_BYTES" ]; then
        local rotated_file
        rotated_file="${logfile}.$(date +%Y%m%d_%H%M%S)"
        parrot_info "Rotating $logfile (size: $(awk "BEGIN {printf \"%.2f\", $size/1024/1024}")MB)"
        
        # Copy and truncate instead of move to avoid breaking file handles
        cp "$logfile" "$rotated_file"
        : > "$logfile"
        
        # Compress the rotated file
        gzip "$rotated_file"
        parrot_info "Compressed to ${rotated_file}.gz"
        
        # Log to audit trail
        parrot_audit_log "log_rotate" "$logfile" "success" "size_mb=$(awk "BEGIN {printf \"%.2f\", $size/1024/1024}")"
    fi
}

# Function to clean old rotated logs
clean_old_logs() {
    local logfile="$1"
    
    # Remove logs older than MAX_AGE_DAYS
    find "$(dirname "$logfile")" -name "$(basename "$logfile").*.gz" -type f -mtime +"$MAX_AGE_DAYS" -delete 2>/dev/null || true
    
    # Keep only MAX_COUNT most recent rotated logs
    local rotated_logs
    rotated_logs=$(find "$(dirname "$logfile")" -name "$(basename "$logfile").*.gz" -type f -printf "%T@ %p\n" 2>/dev/null | \
        sort -rn | awk '{print $2}' || true)
    
    local count=0
    while IFS= read -r rotated_log; do
        count=$((count + 1))
        if [ "$count" -gt "$MAX_COUNT" ]; then
            parrot_info "Removing old rotated log: $rotated_log"
            rm -f "$rotated_log"
        fi
    done <<< "$rotated_logs"
}

# Rotate Parrot MCP Server logs
LOG_FILES=(
    "$PARROT_SERVER_LOG"
    "$PARROT_CLI_LOG"
    "$PARROT_HEALTH_LOG"
    "$PARROT_WORKFLOW_LOG"
    "$PARROT_AUDIT_LOG"
    "$PARROT_METRICS_LOG"
    "$PARROT_JSON_LOG"
)

for logfile in "${LOG_FILES[@]}"; do
    if [ -f "$logfile" ]; then
        rotate_log_file "$logfile"
        clean_old_logs "$logfile"
    fi
done

# Also rotate system logs in /var/log if accessible
if [ -d "/var/log" ] && [ -w "/var/log" ]; then
    for logfile in /var/log/*.log; do
        [ -e "$logfile" ] || continue
        rotate_log_file "$logfile"
        clean_old_logs "$logfile"
    done
fi

parrot_info "Log rotation completed"
