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

# Default values from config or defaults.
# Parse PARROT_LOG_MAX_SIZE which may use K/M/G suffixes (e.g., "100M").
_parse_size_to_mb() {
    local raw="${1:-100M}"
    # Extract numeric part and optional suffix using parameter expansion
    local num="${raw//[^0-9.]/}"
    local suffix
    suffix=$(printf '%s' "$raw" | tr -d '0-9.' | tr '[:lower:]' '[:upper:]')
    case "$suffix" in
        K|KB) awk -v n="$num" 'BEGIN {printf "%.6f", n / 1024}' ;;
        G|GB) awk -v n="$num" 'BEGIN {printf "%.6f", n * 1024}' ;;
        *)    echo "$num" ;;  # M, MB, or bare number -> treat as MB
    esac
}
MAX_SIZE_MB=$(_parse_size_to_mb "${PARROT_LOG_MAX_SIZE:-100M}")
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
    local logdir logbase
    logdir=$(dirname "$logfile")
    logbase=$(basename "$logfile")

    # Remove logs older than MAX_AGE_DAYS; quote glob to avoid shell expansion
    find "$logdir" -name "${logbase}.*.gz" -type f -mtime +"$MAX_AGE_DAYS" -delete 2>/dev/null || true

    # Keep only MAX_COUNT most recent rotated logs.
    # Use portable ls -t (sorted newest-first) instead of GNU find -printf.
    # Use if/fi to avoid the SC2015 A&&B||C pitfall.
    local rotated_logs=""
    if cd "$logdir" 2>/dev/null; then
        rotated_logs=$(ls -1t "${logbase}".*.gz 2>/dev/null || true)
        cd - >/dev/null
    fi

    local count=0
    while IFS= read -r rotated_log; do
        # Skip empty lines defensively
        [ -n "$rotated_log" ] || continue
        count=$((count + 1))
        if [ "$count" -gt "$MAX_COUNT" ]; then
            local full_path="$logdir/$rotated_log"
            parrot_info "Removing old rotated log: $full_path"
            rm -f "$full_path"
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
