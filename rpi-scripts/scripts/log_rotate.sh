#!/bin/bash
# log_rotate.sh - Rotate and compress log files
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-28
# Description: Rotates and compresses /var/log/*.log files.
# Usage: ./log_rotate.sh

set -euo pipefail

LOG_DIR="/var/log"
for logfile in "$LOG_DIR"/*.log; do
	[ -e "$logfile" ] || continue
	rotated_file="$logfile.$(date +%Y%m%d_%H%M%S)"
	mv "$logfile" "$rotated_file"
	gzip "$rotated_file"
	echo "Rotated and compressed $logfile"
done
