#!/bin/bash
# setup_cron.sh - Automate cron job scheduling for system maintenance
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-28
# Description: Installs recommended cron jobs for optimal RPi performance.
# Usage: ./cli.sh setup_cron

set -euo pipefail

CRON_FILE="/tmp/rpi_maintenance_cron"
SCRIPT_DIR="$(dirname "$0")/.."

cat >"$CRON_FILE" <<EOF
# Daily maintenance workflow at 2am
0 2 * * * $SCRIPT_DIR/scripts/daily_workflow.sh >> /var/log/daily_workflow.log 2>&1
# Weekly system update on Sunday at 3am (additional)
0 3 * * 0 $SCRIPT_DIR/cli.sh system_update >> /var/log/system_update.log 2>&1
# Hourly health check
0 * * * * $SCRIPT_DIR/scripts/health_check.sh >> /var/log/health_check.log 2>&1
EOF

crontab "$CRON_FILE"
echo "Cron jobs installed. Use 'crontab -l' to verify."
rm "$CRON_FILE"
