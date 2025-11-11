#!/usr/bin/env bash
# Security Tools Configuration
# This file contains configuration for integrated security testing tools
#
# ⚠️  WARNING: This configuration is for AUTHORIZED SECURITY TESTING ONLY
# Unauthorized use of these tools against systems you do not own or have
# explicit permission to test is ILLEGAL and may result in criminal prosecution.

set -euo pipefail

# Load parent configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common_config.sh"

# =============================================================================
# SECURITY TOOLS BASE CONFIGURATION
# =============================================================================

# Security tools directory
SECURITY_TOOLS_DIR="${SECURITY_TOOLS_DIR:-${SCRIPT_DIR}/security-tools}"
SECURITY_RESULTS_DIR="${SECURITY_RESULTS_DIR:-${SECURITY_TOOLS_DIR}/scan-results}"
SECURITY_CONFIGS_DIR="${SECURITY_CONFIGS_DIR:-${SECURITY_TOOLS_DIR}/configs}"

# Audit log for security operations (separate from main logs)
SECURITY_AUDIT_LOG="${SECURITY_AUDIT_LOG:-${PARROT_LOG_DIR}/security_audit.log}"

# =============================================================================
# AUTHENTICATION & AUTHORIZATION
# =============================================================================

# Basic API key authentication (simple approach until RBAC is implemented)
SECURITY_API_KEY_FILE="${SECURITY_API_KEY_FILE:-${SECURITY_CONFIGS_DIR}/api_keys.conf}"
SECURITY_REQUIRE_AUTH="${SECURITY_REQUIRE_AUTH:-true}"

# Authorized operators (username list, comma-separated)
SECURITY_AUTHORIZED_USERS="${SECURITY_AUTHORIZED_USERS:-root,pi,admin}"

# =============================================================================
# IP WHITELISTING & TARGET VALIDATION
# =============================================================================

# Whitelist file: Only these IP ranges can be scanned
SECURITY_IP_WHITELIST_FILE="${SECURITY_IP_WHITELIST_FILE:-${SECURITY_CONFIGS_DIR}/ip_whitelist.conf}"

# Blacklist file: These IPs/ranges are NEVER allowed
SECURITY_IP_BLACKLIST_FILE="${SECURITY_IP_BLACKLIST_FILE:-${SECURITY_CONFIGS_DIR}/ip_blacklist.conf}"

# Default whitelisted ranges (RFC 1918 private networks)
SECURITY_DEFAULT_WHITELIST=(
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "127.0.0.1/32"
)

# Default blacklist (critical infrastructure, public DNS, etc.)
SECURITY_DEFAULT_BLACKLIST=(
    "0.0.0.0/8"
    "8.8.8.8/32"          # Google DNS
    "8.8.4.4/32"          # Google DNS
    "1.1.1.1/32"          # Cloudflare DNS
    "208.67.222.222/32"   # OpenDNS
)

# =============================================================================
# RATE LIMITING
# =============================================================================

# Maximum scans per hour per user
SECURITY_MAX_SCANS_PER_HOUR="${SECURITY_MAX_SCANS_PER_HOUR:-10}"

# Minimum time between scans (seconds)
SECURITY_MIN_SCAN_INTERVAL="${SECURITY_MIN_SCAN_INTERVAL:-60}"

# Rate limit tracking file
SECURITY_RATE_LIMIT_DB="${SECURITY_RATE_LIMIT_DB:-${SECURITY_TOOLS_DIR}/.rate_limits}"

# =============================================================================
# NMAP CONFIGURATION
# =============================================================================

# Nmap binary path
NMAP_BIN="${NMAP_BIN:-$(which nmap 2>/dev/null || echo '/usr/bin/nmap')}"

# Maximum allowed scan intensity (0-5, where 5 is most aggressive)
NMAP_MAX_INTENSITY="${NMAP_MAX_INTENSITY:-3}"

# Allowed Nmap scan types (comma-separated)
NMAP_ALLOWED_SCAN_TYPES="${NMAP_ALLOWED_SCAN_TYPES:-sS,sT,sU,sV,sC,sn,O}"

# Disallowed Nmap options (dangerous or too aggressive)
# Note: This list is for reference/future use in option validation
# shellcheck disable=SC2034
NMAP_DISALLOWED_OPTIONS=(
    "--script=dos"
    "--script=exploit"
    "--script=brute"
    "--script=vuln"
    "-PE"  # ICMP echo
    "-A"   # Aggressive scan (too broad)
    "--max-rate"  # Can be used for DoS
)

# Maximum number of ports to scan
NMAP_MAX_PORTS="${NMAP_MAX_PORTS:-1000}"

# Scan timeout (seconds)
NMAP_TIMEOUT="${NMAP_TIMEOUT:-300}"

# Nmap results format
NMAP_OUTPUT_FORMAT="${NMAP_OUTPUT_FORMAT:-xml,normal}"

# =============================================================================
# OPENVAS CONFIGURATION
# =============================================================================

# OpenVAS binary/command
OPENVAS_BIN="${OPENVAS_BIN:-$(which gvm-cli 2>/dev/null || echo '/usr/bin/gvm-cli')}"

# OpenVAS socket path (GVM daemon)
OPENVAS_SOCKET="${OPENVAS_SOCKET:-/var/run/gvmd/gvmd.sock}"

# OpenVAS credentials
OPENVAS_USERNAME="${OPENVAS_USERNAME:-admin}"
OPENVAS_PASSWORD_FILE="${OPENVAS_PASSWORD_FILE:-${SECURITY_CONFIGS_DIR}/.openvas_password}"

# Maximum concurrent OpenVAS scans
OPENVAS_MAX_CONCURRENT_SCANS="${OPENVAS_MAX_CONCURRENT_SCANS:-2}"

# OpenVAS scan config (UUID or name)
OPENVAS_SCAN_CONFIG="${OPENVAS_SCAN_CONFIG:-daba56c8-73ec-11df-a475-002264764cea}"  # Full and fast

# Scan timeout (seconds)
OPENVAS_TIMEOUT="${OPENVAS_TIMEOUT:-3600}"

# =============================================================================
# RESULT ENCRYPTION
# =============================================================================

# Encrypt scan results at rest
SECURITY_ENCRYPT_RESULTS="${SECURITY_ENCRYPT_RESULTS:-true}"

# Encryption method (gpg, openssl)
SECURITY_ENCRYPTION_METHOD="${SECURITY_ENCRYPTION_METHOD:-gpg}"

# GPG recipient key ID (if using GPG)
SECURITY_GPG_KEY_ID="${SECURITY_GPG_KEY_ID:-}"

# OpenSSL cipher (if using OpenSSL)
SECURITY_OPENSSL_CIPHER="${SECURITY_OPENSSL_CIPHER:-aes-256-cbc}"

# Results retention period (days)
SECURITY_RESULTS_RETENTION_DAYS="${SECURITY_RESULTS_RETENTION_DAYS:-30}"

# =============================================================================
# SANDBOXING & ISOLATION
# =============================================================================

# Use Docker containers for tool execution
SECURITY_USE_DOCKER="${SECURITY_USE_DOCKER:-false}"

# Docker image for security tools
SECURITY_DOCKER_IMAGE="${SECURITY_DOCKER_IMAGE:-kalilinux/kali-rolling}"

# Use network namespace isolation
SECURITY_USE_NETNS="${SECURITY_USE_NETNS:-false}"

# Dedicated network namespace name
SECURITY_NETNS_NAME="${SECURITY_NETNS_NAME:-parrot_security}"

# =============================================================================
# NOTIFICATION SETTINGS
# =============================================================================

# Notify on scan completion
SECURITY_NOTIFY_ON_COMPLETION="${SECURITY_NOTIFY_ON_COMPLETION:-true}"

# Notify on scan errors
SECURITY_NOTIFY_ON_ERROR="${SECURITY_NOTIFY_ON_ERROR:-true}"

# Notification email (inherits from parent config if not set)
SECURITY_NOTIFY_EMAIL="${SECURITY_NOTIFY_EMAIL:-${PARROT_ALERT_EMAIL}}"

# =============================================================================
# COMPLIANCE & LEGAL
# =============================================================================

# Require acknowledgment of authorized use
SECURITY_REQUIRE_ACKNOWLEDGMENT="${SECURITY_REQUIRE_ACKNOWLEDGMENT:-true}"

# Legal disclaimer file (must be acknowledged before first use)
SECURITY_LEGAL_DISCLAIMER="${SECURITY_LEGAL_DISCLAIMER:-${SECURITY_TOOLS_DIR}/LEGAL_NOTICE.txt}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Initialize security tools directories and files
security_init() {
    # Create directories
    mkdir -p "$SECURITY_RESULTS_DIR"
    mkdir -p "$SECURITY_CONFIGS_DIR"

    # Set restrictive permissions
    chmod 700 "$SECURITY_TOOLS_DIR"
    chmod 700 "$SECURITY_RESULTS_DIR"
    chmod 700 "$SECURITY_CONFIGS_DIR"

    # Create audit log
    touch "$SECURITY_AUDIT_LOG"
    chmod 600 "$SECURITY_AUDIT_LOG"

    # Initialize rate limit database
    touch "$SECURITY_RATE_LIMIT_DB"
    chmod 600 "$SECURITY_RATE_LIMIT_DB"

    # Create whitelist file if it doesn't exist
    if [ ! -f "$SECURITY_IP_WHITELIST_FILE" ]; then
        {
            echo "# IP Whitelist for Security Scanning"
            echo "# Only these IP ranges are allowed to be scanned"
            echo "# Format: CIDR notation, one per line"
            echo ""
            printf '%s\n' "${SECURITY_DEFAULT_WHITELIST[@]}"
        } > "$SECURITY_IP_WHITELIST_FILE"
        chmod 600 "$SECURITY_IP_WHITELIST_FILE"
    fi

    # Create blacklist file if it doesn't exist
    if [ ! -f "$SECURITY_IP_BLACKLIST_FILE" ]; then
        {
            echo "# IP Blacklist for Security Scanning"
            echo "# These IP ranges are NEVER allowed to be scanned"
            echo "# Format: CIDR notation, one per line"
            echo ""
            printf '%s\n' "${SECURITY_DEFAULT_BLACKLIST[@]}"
        } > "$SECURITY_IP_BLACKLIST_FILE"
        chmod 600 "$SECURITY_IP_BLACKLIST_FILE"
    fi

    # Create API key file if it doesn't exist
    if [ ! -f "$SECURITY_API_KEY_FILE" ]; then
        {
            echo "# API Keys for Security Tools"
            echo "# Format: username:api_key_hash"
            echo "# Generate with: echo -n 'your_api_key' | sha256sum"
            echo ""
        } > "$SECURITY_API_KEY_FILE"
        chmod 600 "$SECURITY_API_KEY_FILE"
    fi

    parrot_info "Security tools initialized successfully"
}

# Audit log function (always logs, regardless of PARROT_CURRENT_LOG)
security_audit() {
    local level="$1"
    shift
    local message="$*"

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local msgid
    msgid=$(date +%s%N)

    local user="${SUDO_USER:-${USER:-unknown}}"
    local remote_addr="${SSH_CLIENT%% *}"
    [ -z "$remote_addr" ] && remote_addr="localhost"

    # Audit log format: [timestamp] [level] [msgid] [user@remote] message
    echo "[$timestamp] [$level] [msgid:$msgid] [$user@$remote_addr] $message" >> "$SECURITY_AUDIT_LOG"

    # Also log to main parrot log
    parrot_log "$level" "SECURITY: $message"
}

# Check if user is authorized
security_check_user() {
    local user="${1:-${SUDO_USER:-${USER}}}"

    if [[ ",$SECURITY_AUTHORIZED_USERS," == *",$user,"* ]]; then
        return 0
    else
        security_audit "ERROR" "Unauthorized access attempt by user: $user"
        return 1
    fi
}

# Validate API key (simple hash-based validation)
security_validate_api_key() {
    local api_key="$1"
    local user="$2"

    if [ "$SECURITY_REQUIRE_AUTH" != "true" ]; then
        return 0
    fi

    if [ ! -f "$SECURITY_API_KEY_FILE" ]; then
        security_audit "ERROR" "API key file not found"
        return 1
    fi

    # Hash the provided key
    local key_hash
    key_hash=$(echo -n "$api_key" | sha256sum | awk '{print $1}')

    # Check if hash exists for this user
    if grep -q "^${user}:${key_hash}$" "$SECURITY_API_KEY_FILE"; then
        return 0
    else
        security_audit "ERROR" "Invalid API key for user: $user"
        return 1
    fi
}

# Check rate limit for user
security_check_rate_limit() {
    local user="$1"
    local operation="$2"

    local now
    now=$(date +%s)

    local hour_ago=$((now - 3600))

    # Count operations in last hour
    local count
    count=$(grep -c "^${user}:${operation}:" "$SECURITY_RATE_LIMIT_DB" 2>/dev/null || echo 0)

    # Clean old entries
    sed -i "/^${user}:${operation}:[0-9]*$/d" "$SECURITY_RATE_LIMIT_DB" 2>/dev/null || true

    # Re-count after cleanup
    count=$(awk -F: -v user="$user" -v op="$operation" -v cutoff="$hour_ago" \
        '$1 == user && $2 == op && $3 >= cutoff' \
        "$SECURITY_RATE_LIMIT_DB" 2>/dev/null | wc -l)

    if [ "$count" -ge "$SECURITY_MAX_SCANS_PER_HOUR" ]; then
        security_audit "WARN" "Rate limit exceeded for user: $user (${count}/${SECURITY_MAX_SCANS_PER_HOUR})"
        return 1
    fi

    # Record this operation
    echo "${user}:${operation}:${now}" >> "$SECURITY_RATE_LIMIT_DB"

    return 0
}

# Validate IP address against whitelist/blacklist
security_validate_target() {
    local target="$1"

    # Check if ipcalc or similar tool is available
    if ! command -v ipcalc >/dev/null 2>&1; then
        security_audit "WARN" "ipcalc not available, skipping IP validation"
        return 0
    fi

    # Check blacklist first
    while IFS= read -r blacklist_entry; do
        # Skip comments and empty lines
        [[ "$blacklist_entry" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$blacklist_entry" ]] && continue

        if ipcalc -c "$target" "$blacklist_entry" >/dev/null 2>&1; then
            security_audit "ERROR" "Target $target is blacklisted (matches $blacklist_entry)"
            return 1
        fi
    done < "$SECURITY_IP_BLACKLIST_FILE"

    # Check whitelist
    local whitelisted=false
    while IFS= read -r whitelist_entry; do
        # Skip comments and empty lines
        [[ "$whitelist_entry" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$whitelist_entry" ]] && continue

        if ipcalc -c "$target" "$whitelist_entry" >/dev/null 2>&1; then
            whitelisted=true
            break
        fi
    done < "$SECURITY_IP_WHITELIST_FILE"

    if [ "$whitelisted" = false ]; then
        security_audit "ERROR" "Target $target is not whitelisted"
        return 1
    fi

    return 0
}

# Encrypt scan results
security_encrypt_file() {
    local input_file="$1"
    local output_file="${input_file}.enc"

    if [ "$SECURITY_ENCRYPT_RESULTS" != "true" ]; then
        echo "$input_file"
        return 0
    fi

    case "$SECURITY_ENCRYPTION_METHOD" in
        gpg)
            if [ -z "$SECURITY_GPG_KEY_ID" ]; then
                security_audit "ERROR" "GPG encryption enabled but no key ID configured"
                echo "$input_file"
                return 1
            fi
            gpg --encrypt --recipient "$SECURITY_GPG_KEY_ID" --output "$output_file" "$input_file"
            rm -f "$input_file"
            ;;
        openssl)
            openssl enc "-${SECURITY_OPENSSL_CIPHER}" -salt -in "$input_file" -out "$output_file" \
                -pass "pass:$(openssl rand -base64 32)"
            rm -f "$input_file"
            ;;
        *)
            security_audit "ERROR" "Unknown encryption method: $SECURITY_ENCRYPTION_METHOD"
            echo "$input_file"
            return 1
            ;;
    esac

    echo "$output_file"
    return 0
}

# Clean old results
security_cleanup_old_results() {
    find "$SECURITY_RESULTS_DIR" -type f -mtime +"$SECURITY_RESULTS_RETENTION_DAYS" -delete
    security_audit "INFO" "Cleaned results older than $SECURITY_RESULTS_RETENTION_DAYS days"
}

# Export functions for use in child scripts
export -f security_audit
export -f security_check_user
export -f security_validate_api_key
export -f security_check_rate_limit
export -f security_validate_target
export -f security_encrypt_file
export -f security_cleanup_old_results

# Initialize on source
security_init
