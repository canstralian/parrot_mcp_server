#!/bin/bash
# backup_home.sh - Backup the /home directory
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-28
# Description: Creates a compressed backup of the /home directory.
# Usage: ./cli.sh backup_home [backup_dir]

set -euo pipefail

BACKUP_DIR="${1:-/var/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/home_backup_$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"
sudo tar -czf "$BACKUP_FILE" /home

echo "Backup created at $BACKUP_FILE"
