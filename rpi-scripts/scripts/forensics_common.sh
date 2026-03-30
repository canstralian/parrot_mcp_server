#!/usr/bin/env bash
# forensics_common.sh - Common utilities for forensics scripts
# Author: Canstralian
# Description: Shared functions for memory and disk forensics operations
# Usage: source this file in forensics scripts

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# ============================================================================
# FORENSICS CONFIGURATION
# ============================================================================

# Forensics directories
PARROT_FORENSICS_DIR="${PARROT_FORENSICS_DIR:-${PARROT_BASE_DIR}/forensics}"
PARROT_FORENSICS_CACHE="${PARROT_FORENSICS_CACHE:-${PARROT_FORENSICS_DIR}/cache}"
PARROT_FORENSICS_RESULTS="${PARROT_FORENSICS_RESULTS:-${PARROT_FORENSICS_DIR}/results}"
PARROT_FORENSICS_LOG="${PARROT_FORENSICS_LOG:-${PARROT_LOG_DIR}/forensics.log}"

# Ensure forensics directories exist
mkdir -p "$PARROT_FORENSICS_DIR" "$PARROT_FORENSICS_CACHE" "$PARROT_FORENSICS_RESULTS"

# Set script-specific log file
export PARROT_CURRENT_LOG="$PARROT_FORENSICS_LOG"

# ============================================================================
# DEPENDENCY CHECKING
# ============================================================================

# Check if a command is available
forensics_check_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command -v "$cmd" &>/dev/null; then
        parrot_error "Required command '$cmd' not found"
        if [ -n "$install_hint" ]; then
            parrot_warn "Install hint: $install_hint"
        fi
        return 1
    fi
    return 0
}

# Check if Python package is available
forensics_check_python_package() {
    local package="$1"
    local install_hint="${2:-pip install $package}"
    
    if ! python3 -c "import $package" 2>/dev/null; then
        parrot_error "Required Python package '$package' not found"
        parrot_warn "Install hint: $install_hint"
        return 1
    fi
    return 0
}

# Check all forensics dependencies
forensics_check_dependencies() {
    local all_ok=0
    
    parrot_info "Checking forensics dependencies..."
    
    # Check Python 3
    if ! forensics_check_command "python3" "apt-get install python3"; then
        all_ok=1
    fi
    
    # Check pip
    if ! forensics_check_command "pip3" "apt-get install python3-pip"; then
        all_ok=1
    fi
    
    return $all_ok
}

# ============================================================================
# RESULT MANAGEMENT
# ============================================================================

# Generate unique analysis ID
forensics_generate_id() {
    local prefix="${1:-analysis}"
    echo "${prefix}_$(date +%Y%m%d_%H%M%S)_$$"
}

# Create result directory for analysis
forensics_create_result_dir() {
    local analysis_id="$1"
    local result_dir="${PARROT_FORENSICS_RESULTS}/${analysis_id}"
    
    mkdir -p "$result_dir"
    echo "$result_dir"
}

# Save result to file
forensics_save_result() {
    local analysis_id="$1"
    local result_file="$2"
    local content="$3"
    
    local result_dir
    result_dir=$(forensics_create_result_dir "$analysis_id")
    local full_path="${result_dir}/${result_file}"
    
    echo "$content" > "$full_path"
    parrot_info "Result saved to: $full_path"
    echo "$full_path"
}

# ============================================================================
# FORMAT CONVERSION
# ============================================================================

# Convert result to JSON format
forensics_to_json() {
    local input="$1"
    local output="${2:-/dev/stdout}"
    
    # Simple JSON wrapper for results
    cat > "$output" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "results": $(echo "$input" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
}
EOF
}

# Convert result to CSV format
forensics_to_csv() {
    local input="$1"
    local output="${2:-/dev/stdout}"
    
    # Echo CSV header and content
    echo "$input" > "$output"
}

# ============================================================================
# PROGRESS REPORTING
# ============================================================================

# Report progress for long-running operations
forensics_report_progress() {
    local operation="$1"
    local percent="${2:-}"
    local message="${3:-}"
    
    local progress_msg="$operation"
    if [ -n "$percent" ]; then
        progress_msg="$progress_msg ($percent%)"
    fi
    if [ -n "$message" ]; then
        progress_msg="$progress_msg: $message"
    fi
    
    parrot_info "$progress_msg"
}

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

# Check if cached result exists
forensics_check_cache() {
    local cache_key="$1"
    local cache_file="${PARROT_FORENSICS_CACHE}/${cache_key}.cache"
    
    if [ -f "$cache_file" ]; then
        # Check if cache is still valid (less than 24 hours old)
        local cache_age
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file")))
        if [ "$cache_age" -lt 86400 ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

# Save result to cache
forensics_save_cache() {
    local cache_key="$1"
    local content="$2"
    local cache_file="${PARROT_FORENSICS_CACHE}/${cache_key}.cache"
    
    echo "$content" > "$cache_file"
    parrot_info "Result cached: $cache_key"
}

# ============================================================================
# HASH COMPUTATION
# ============================================================================

# Compute hash of file
forensics_compute_hash() {
    local file="$1"
    local algorithm="${2:-sha256}"
    
    case "$algorithm" in
        md5)
            md5sum "$file" | awk '{print $1}'
            ;;
        sha1)
            sha1sum "$file" | awk '{print $1}'
            ;;
        sha256|*)
            sha256sum "$file" | awk '{print $1}'
            ;;
    esac
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Handle forensics errors gracefully
forensics_handle_error() {
    local operation="$1"
    local error_msg="$2"
    local exit_code="${3:-1}"
    
    parrot_error "Forensics operation failed: $operation"
    parrot_error "Error: $error_msg"
    
    return "$exit_code"
}

# Export functions for use in other scripts
export -f forensics_check_command
export -f forensics_check_python_package
export -f forensics_check_dependencies
export -f forensics_generate_id
export -f forensics_create_result_dir
export -f forensics_save_result
export -f forensics_to_json
export -f forensics_to_csv
export -f forensics_report_progress
export -f forensics_check_cache
export -f forensics_save_cache
export -f forensics_compute_hash
export -f forensics_handle_error
