#!/usr/bin/env bash
# =============================================================================
# setup_cron.sh - Automate cron job scheduling for system maintenance
#
# Description:
#   Installs recommended cron jobs for optimal RPi performance.
#   Uses secure temporary file creation.
#
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-11-12 (Production Release)
#
# Usage:
#   ./cli.sh setup_cron
#
# Security:
#   - Uses mktemp for secure temporary file creation
#   - Validates crontab before installation
#   - Proper error handling
# =============================================================================

set -euo pipefail

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/../common_config.sh"

# Initialize logging
parrot_init_log_dir
PARROT_CURRENT_LOG="$PARROT_WORKFLOW_LOG"

# Create secure temporary file
CRON_FILE=$(mktemp) || {
    parrot_error "Failed to create temporary file"
    exit 1
}

cat >"$CRON_FILE" <<EOF
# Daily maintenance workflow at 2am
0 2 * * * $SCRIPT_DIR/scripts/daily_workflow.sh >> /var/log/daily_workflow.log 2>&1
# Weekly system update on Sunday at 3am (additional)
0 3 * * 0 $SCRIPT_DIR/cli.sh system_update >> /var/log/system_update.log 2>&1
# Hourly health check
0 * * * * $SCRIPT_DIR/scripts/health_check.sh >> /var/log/health_check.log 2>&1
EOF

# Trap to ensure cleanup
trap 'rm -f "$CRON_FILE"' EXIT INT TERM

# Validate cron file syntax
if ! grep -qE '^[0-9*]' "$CRON_FILE"; then
    parrot_error "Invalid cron syntax in generated file"
    exit 1
fi

# Install crontab
parrot_info "Installing cron jobs..."
if crontab "$CRON_FILE"; then
    parrot_info "Cron jobs installed successfully"
    echo "✓ Cron jobs installed. Use 'crontab -l' to verify."
else
    parrot_error "Failed to install crontab"
    exit 1
fi

# Verify installation
if crontab -l | grep -q "health_check.sh"; then
    parrot_info "Crontab verification successful"
else
    parrot_warn "Crontab verification failed (manual check recommended)"
fi

# Cleanup is handled by trap
exit 0
