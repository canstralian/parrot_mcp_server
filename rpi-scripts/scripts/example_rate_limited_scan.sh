#!/usr/bin/env bash
# Example script demonstrating rate limiter usage
# This script shows how to use parrot_check_rate_limit to protect operations

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../common_config.sh" ]; then
    # shellcheck source=../common_config.sh disable=SC1091
    source "${SCRIPT_DIR}/../common_config.sh"
else
    echo "ERROR: Cannot find common_config.sh" >&2
    exit 1
fi

# Set script-specific log file
export PARROT_CURRENT_LOG="$PARROT_LOG_DIR/example_scan.log"

# Initialize log directory
parrot_init_log_dir

# Example function that performs a "scan" operation
perform_scan() {
    local user="$1"
    
    parrot_info "Performing scan for user: $user"
    
    # Simulate some work
    sleep 0.1
    
    parrot_info "Scan completed successfully"
}

# Main function
main() {
    local user="${1:-defaultuser}"
    
    parrot_info "Example rate-limited scan script started"
    
    # Check rate limit before performing the operation
    if ! parrot_check_rate_limit "$user" "scan"; then
        parrot_error "Rate limit exceeded for user '$user'"
        echo "ERROR: Too many scan requests. Please try again later."
        exit 1
    fi
    
    # Rate limit check passed, perform the operation
    perform_scan "$user"
    
    echo "Scan completed successfully for user: $user"
    parrot_info "Example rate-limited scan script completed"
}

# Run main function
main "$@"
