#!/usr/bin/env bash
# common_config.sh - Centralized configuration and utility functions for Parrot MCP Server
# Usage: source "$(dirname "$0")/common_config.sh" at the top of your script

set -euo pipefail

# ============================================================================
# CONFIGURATION LOADER
# ============================================================================

# Determine base directory
PARROT_BASE_DIR="${PARROT_BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PARROT_SCRIPT_DIR="${PARROT_SCRIPT_DIR:-${PARROT_BASE_DIR}/rpi-scripts}"

# Load user configuration if exists (but don't fail if it doesn't)
if [ -f "${PARROT_SCRIPT_DIR}/config.env" ]; then
    # shellcheck disable=SC1091
    source "${PARROT_SCRIPT_DIR}/config.env"
fi

# ============================================================================
# DEFAULT CONFIGURATION VALUES
# ============================================================================

# Paths and Directories
PARROT_LOG_DIR="${PARROT_LOG_DIR:-${PARROT_BASE_DIR}/logs}"
# Use /run/user/$(id -u) if available, otherwise fall back to project runtime directory
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ]; then
    PARROT_IPC_DIR="${PARROT_IPC_DIR:-${XDG_RUNTIME_DIR}/parrot_mcp}"
else
    PARROT_IPC_DIR="${PARROT_IPC_DIR:-${PARROT_BASE_DIR}/runtime}"
fi
PARROT_PID_FILE="${PARROT_PID_FILE:-${PARROT_LOG_DIR}/mcp_server.pid}"

# Logging Configuration
PARROT_SERVER_LOG="${PARROT_SERVER_LOG:-${PARROT_LOG_DIR}/parrot.log}"
PARROT_CLI_LOG="${PARROT_CLI_LOG:-${PARROT_LOG_DIR}/cli_error.log}"
PARROT_HEALTH_LOG="${PARROT_HEALTH_LOG:-${PARROT_LOG_DIR}/health_check.log}"
PARROT_WORKFLOW_LOG="${PARROT_WORKFLOW_LOG:-${PARROT_LOG_DIR}/daily_workflow.log}"
PARROT_LOG_MAX_SIZE="${PARROT_LOG_MAX_SIZE:-10M}"
PARROT_LOG_MAX_AGE="${PARROT_LOG_MAX_AGE:-30}"
PARROT_LOG_ROTATION_COUNT="${PARROT_LOG_ROTATION_COUNT:-5}"
PARROT_LOG_LEVEL="${PARROT_LOG_LEVEL:-INFO}"

# MCP Server Configuration - Using named pipes for secure IPC
PARROT_MCP_INPUT_PIPE="${PARROT_MCP_INPUT_PIPE:-${PARROT_IPC_DIR}/mcp_in.pipe}"
PARROT_MCP_OUTPUT_PIPE="${PARROT_MCP_OUTPUT_PIPE:-${PARROT_IPC_DIR}/mcp_out.pipe}"
PARROT_MCP_BAD="${PARROT_MCP_BAD:-${PARROT_IPC_DIR}/mcp_bad.json}"
PARROT_MCP_PORT="${PARROT_MCP_PORT:-3000}"
PARROT_MCP_HOST="${PARROT_MCP_HOST:-127.0.0.1}"
PARROT_MCP_TLS="${PARROT_MCP_TLS:-false}"

# System Monitoring Thresholds
PARROT_DISK_THRESHOLD="${PARROT_DISK_THRESHOLD:-80}"
PARROT_LOAD_THRESHOLD="${PARROT_LOAD_THRESHOLD:-2.0}"
PARROT_MEM_THRESHOLD="${PARROT_MEM_THRESHOLD:-90}"

# Notification Settings
PARROT_ALERT_EMAIL="${PARROT_ALERT_EMAIL:-}"
PARROT_NOTIFY_EMAIL="${PARROT_NOTIFY_EMAIL:-}"
PARROT_EMAIL_PREFIX="${PARROT_EMAIL_PREFIX:-[Parrot MCP]}"

# Maintenance Settings
PARROT_AUTO_UPDATE="${PARROT_AUTO_UPDATE:-false}"
PARROT_AUTO_CLEAN="${PARROT_AUTO_CLEAN:-true}"
PARROT_CACHE_MAX_AGE="${PARROT_CACHE_MAX_AGE:-7}"
PARROT_BACKUP_DIR="${PARROT_BACKUP_DIR:-${HOME}/backups}"
PARROT_BACKUP_RETENTION="${PARROT_BACKUP_RETENTION:-30}"

# Security Settings
PARROT_RUN_AS_USER="${PARROT_RUN_AS_USER:-}"
PARROT_STRICT_PERMS="${PARROT_STRICT_PERMS:-true}"
PARROT_VALIDATION_LEVEL="${PARROT_VALIDATION_LEVEL:-STRICT}"
PARROT_MAX_INPUT_SIZE="${PARROT_MAX_INPUT_SIZE:-1048576}"

# Retry and Timeout Settings
PARROT_RETRY_COUNT="${PARROT_RETRY_COUNT:-3}"
PARROT_RETRY_DELAY="${PARROT_RETRY_DELAY:-5}"
PARROT_COMMAND_TIMEOUT="${PARROT_COMMAND_TIMEOUT:-300}"

# Development and Debugging
PARROT_DEBUG="${PARROT_DEBUG:-false}"
PARROT_DRY_RUN="${PARROT_DRY_RUN:-false}"
PARROT_TRACE="${PARROT_TRACE:-false}"

# Cron Schedule
PARROT_CRON_DAILY="${PARROT_CRON_DAILY:-0 2 * * *}"
PARROT_CRON_BACKUP="${PARROT_CRON_BACKUP:-0 3 * * 0}"
PARROT_CRON_HEALTH="${PARROT_CRON_HEALTH:-0 * * * *}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Initialize log directory
parrot_init_log_dir() {
    if [ ! -d "$PARROT_LOG_DIR" ]; then
        mkdir -p "$PARROT_LOG_DIR" || {
            echo "ERROR: Failed to create log directory: $PARROT_LOG_DIR" >&2
            return 1
        }
    fi

    if [ "$PARROT_STRICT_PERMS" = "true" ]; then
        chmod 700 "$PARROT_LOG_DIR" 2>/dev/null || true
    fi
}

# Structured logging function
# Usage: parrot_log LEVEL "message"
parrot_log() {
    local level="$1"
    shift
    local message="$*"
    local log_file="${PARROT_CURRENT_LOG:-$PARROT_SERVER_LOG}"
    local msgid

    # Generate unique message ID using nanosecond timestamp
    msgid="$(date +%s%N)"

    # Ensure log directory exists
    parrot_init_log_dir

    # Check if we should log this level
    local should_log=false
    case "$PARROT_LOG_LEVEL" in
        DEBUG) should_log=true ;;
        INFO)
            [[ "$level" =~ ^(INFO|WARN|ERROR)$ ]] && should_log=true
            ;;
        WARN)
            [[ "$level" =~ ^(WARN|ERROR)$ ]] && should_log=true
            ;;
        ERROR)
            [[ "$level" = "ERROR" ]] && should_log=true
            ;;
    esac

    if [ "$should_log" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [msgid:$msgid] $message" >> "$log_file"
    fi

    # Also output to stderr for ERROR level
    if [ "$level" = "ERROR" ]; then
        echo "ERROR: $message" >&2
    fi

    # Output to stdout in debug mode
    if [ "$PARROT_DEBUG" = "true" ]; then
        echo "[$level] $message"
    fi
}

# Convenience logging functions
parrot_debug() { parrot_log "DEBUG" "$@"; }
parrot_info() { parrot_log "INFO" "$@"; }
parrot_warn() { parrot_log "WARN" "$@"; }
parrot_error() { parrot_log "ERROR" "$@"; }

# Input validation functions
parrot_validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

parrot_validate_number() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    return 0
}

parrot_validate_percentage() {
    local value="$1"
    if ! parrot_validate_number "$value"; then
        return 1
    fi
    if [ "$value" -lt 0 ] || [ "$value" -gt 100 ]; then
        return 1
    fi
    return 0
}

parrot_validate_path() {
    # Validate that $1 is a safe, relative path within $PARROT_BASE_DIR.
    # - Rejects absolute paths, path traversal, and null bytes.
    # - Only allows paths that resolve within $PARROT_BASE_DIR.
    local path="$1"

    # Reject null bytes
    if [[ "$path" == *$'\0'* ]]; then
        return 1
    fi

    # Reject absolute paths
    if [[ "$path" = /* ]]; then
        return 1
    fi

    # Reject path traversal attempts
    if [[ "$path" == *".."* ]]; then
        return 1
    fi

    # Resolve the path and ensure it is within $PARROT_BASE_DIR
    local resolved
    resolved="$(realpath -m "${PARROT_BASE_DIR}/${path}" 2>/dev/null)"
    if [ -z "$resolved" ]; then
        return 1
    fi
    case "$resolved" in
        "$PARROT_BASE_DIR"/*) return 0 ;;
        *) return 1 ;;
    esac
}

parrot_validate_script_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        return 1
    fi
    return 0
}

# Validate IPv4 address
parrot_validate_ipv4() {
    local ip="$1"
    local octet="([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])"
    if [[ ! "$ip" =~ ^${octet}\.${octet}\.${octet}\.${octet}$ ]]; then
        return 1
    fi
    return 0
}

# Validate port number (1-65535)
parrot_validate_port() {
    local port="$1"
    if ! parrot_validate_number "$port"; then
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# Sanitize input by removing dangerous characters.
# Removes null bytes and carriage returns, and strips all non-printable characters
# except for newlines and tabs. Tabs are preserved to allow for legitimate tabular data.
# This ensures input is safe for logging and protocol exchange, per MCP compliance.
parrot_sanitize_input() {
    local input="$1"
    echo "$input" | tr -d '\000\r' | tr -cd '[:print:]\n\t'
}

# Check if running as root
parrot_is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Check if a command exists
parrot_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Send notification email if configured
parrot_send_notification() {
    local subject="$1"
    local message="$2"
    local recipient="${3:-$PARROT_ALERT_EMAIL}"

    if [ -z "$recipient" ]; then
        parrot_debug "Email notifications disabled (no recipient configured)"
        return 0
    fi

    if ! parrot_validate_email "$recipient"; then
        parrot_error "Invalid email address: $recipient"
        return 1
    fi

    if ! parrot_command_exists "mail"; then
        parrot_warn "Cannot send email: 'mail' command not found"
        return 1
    fi

    if [ "$PARROT_DRY_RUN" = "true" ]; then
        parrot_info "DRY RUN: Would send email to $recipient: $subject"
        return 0
    fi

    echo "$message" | mail -s "${PARROT_EMAIL_PREFIX} $subject" "$recipient"
}

# Retry a command with exponential backoff
parrot_retry() {
    local max_attempts="$PARROT_RETRY_COUNT"
    local attempt=1
    local delay="$PARROT_RETRY_DELAY"

    # Check if first argument is a number
    if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        max_attempts="$1"
        shift
    fi

    local cmd=("$@")

    while [ "$attempt" -le "$max_attempts" ]; do
        parrot_debug "Attempt $attempt/$max_attempts: ${cmd[*]}"

        if "${cmd[@]}"; then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            parrot_warn "Command failed, retrying in ${delay}s... (attempt $attempt/$max_attempts)"
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi

        attempt=$((attempt + 1))
    done

    parrot_error "Command failed after $max_attempts attempts: ${cmd[*]}"
    return 1
}

# Check file permissions
parrot_check_perms() {
    local file="$1"
    local expected_perms="$2"

    if [ ! -e "$file" ]; then
        parrot_error "File does not exist: $file"
        return 1
    fi

    local actual_perms
    actual_perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)

    if [ "$actual_perms" != "$expected_perms" ]; then
        parrot_warn "Incorrect permissions on $file: $actual_perms (expected: $expected_perms)"
        if [ "$PARROT_STRICT_PERMS" = "true" ]; then
            return 1
        fi
    fi

    return 0
}

# Create secure temporary file
parrot_mktemp() {
    local template="${1:-parrot.XXXXXX}"
    local tmpfile

    if ! tmpfile=$(mktemp -t "$template"); then
        parrot_error "Failed to create temporary file"
        return 1
    fi

    chmod 600 "$tmpfile"
    echo "$tmpfile"
}

# Validate JSON input
parrot_validate_json() {
    local json_file="$1"

    if [ ! -f "$json_file" ]; then
        parrot_error "JSON file does not exist: $json_file"
        return 1
    fi

    # Check file size
    local size
    size=$(stat -c%s "$json_file" 2>/dev/null || stat -f%z "$json_file" 2>/dev/null)
    if [ "$size" -gt "$PARROT_MAX_INPUT_SIZE" ]; then
        parrot_error "JSON file exceeds maximum size: $size > $PARROT_MAX_INPUT_SIZE"
        return 1
    fi

    # Validate JSON syntax if jq is available
    if parrot_command_exists "jq"; then
        if ! jq empty "$json_file" >/dev/null 2>&1; then
            parrot_error "Invalid JSON syntax in: $json_file"
            return 1
        fi
    else
        parrot_warn "jq not available, skipping JSON validation"
    fi

    return 0
}

# Initialize IPC directory with secure permissions
parrot_init_ipc_dir() {
    if [ ! -d "$PARROT_IPC_DIR" ]; then
        # Set umask to restrict permissions before creating directory
        local old_umask
        old_umask=$(umask)
        umask 0077
        mkdir -p "$PARROT_IPC_DIR" || {
            umask "$old_umask"
            parrot_error "Failed to create IPC directory: $PARROT_IPC_DIR"
            return 1
        }
        umask "$old_umask"
        parrot_debug "Created IPC directory: $PARROT_IPC_DIR with mode 700"
    fi

    # Ensure directory has correct permissions
    if [ "$PARROT_STRICT_PERMS" = "true" ]; then
        chmod 700 "$PARROT_IPC_DIR" 2>/dev/null || true
    fi

    return 0
}

# Create a secure named pipe with restricted permissions
parrot_create_pipe() {
    local pipe_path="$1"

    # Ensure IPC directory exists
    parrot_init_ipc_dir || return 1

    # Remove existing pipe if present
    if [ -p "$pipe_path" ]; then
        rm -f "$pipe_path"
    elif [ -e "$pipe_path" ]; then
        parrot_error "Path exists but is not a pipe: $pipe_path"
        return 1
    fi

    # Set umask to create pipe with restricted permissions (0600)
    local old_umask
    old_umask=$(umask)
    umask 0077

    # Create the named pipe
    if ! mkfifo "$pipe_path"; then
        umask "$old_umask"
        parrot_error "Failed to create named pipe: $pipe_path"
        return 1
    fi

    umask "$old_umask"
    parrot_debug "Created named pipe: $pipe_path with mode 600"
    return 0
}

# Clean up named pipes
parrot_cleanup_pipes() {
    local pipes=("$@")
    for pipe in "${pipes[@]}"; do
        if [ -p "$pipe" ]; then
            rm -f "$pipe"
            parrot_debug "Removed named pipe: $pipe"
        fi
    done
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Enable trace mode if configured
if [ "$PARROT_TRACE" = "true" ]; then
    set -x
fi

# Ensure log directory exists
parrot_init_log_dir

# Log configuration loading
parrot_debug "Configuration loaded from: ${PARROT_SCRIPT_DIR}/config.env"
parrot_debug "Base directory: $PARROT_BASE_DIR"
parrot_debug "Log directory: $PARROT_LOG_DIR"
parrot_debug "IPC directory: $PARROT_IPC_DIR"

# Export commonly used variables for child processes
export PARROT_BASE_DIR PARROT_SCRIPT_DIR PARROT_LOG_DIR
export PARROT_DEBUG PARROT_DRY_RUN

# ============================================================================
# END OF CONFIGURATION
# ============================================================================
