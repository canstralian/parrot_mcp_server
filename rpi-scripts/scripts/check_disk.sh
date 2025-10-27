#!/bin/bash
# check_disk.sh - Check disk usage and report
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-28
# Description: Reports disk usage and alerts if usage exceeds threshold.
# Usage: ./check_disk.sh [threshold_percent]

set -euo pipefail

THRESHOLD="${1:-80}"
USAGE=$(df --output=pcent / | tail -1 | awk '{gsub(/%/,""); print $1}')

if [ "$USAGE" -ge "$THRESHOLD" ]; then
	echo "Warning: Disk usage is at ${USAGE}% (threshold: ${THRESHOLD}%)" >&2
else
	echo "Disk usage is at ${USAGE}% (threshold: ${THRESHOLD}%)"
fi
