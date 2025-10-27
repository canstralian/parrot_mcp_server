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

cat > "$CRON_FILE" <<EOF
# System update every Sunday at 2am
0 2 * * 0 $SCRIPT_DIR/cli.sh system_update >> /var/log/system_update.log 2>&1
# Clean cache daily at 3am
0 3 * * * $SCRIPT_DIR/cli.sh clean_cache >> /var/log/clean_cache.log 2>&1
# Check disk usage every hour
0 * * * * $SCRIPT_DIR/cli.sh check_disk 90 >> /var/log/check_disk.log 2>&1
# Backup /home every night at 1am
0 1 * * * $SCRIPT_DIR/cli.sh backup_home /var/backups >> /var/log/backup_home.log 2>&1
# Rotate logs weekly
0 4 * * 0 $SCRIPT_DIR/cli.sh log_rotate >> /var/log/log_rotate.log 2>&1
EOF

crontab "$CRON_FILE"
echo "Cron jobs installed. Use 'crontab -l' to verify."
rm "$CRON_FILE"
