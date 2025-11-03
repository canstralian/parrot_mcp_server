#!/bin/bash
# system_update.sh - Update and upgrade system packages
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-30
# Description: Updates package lists, upgrades all packages, cleans up unused packages, and checks if a reboot is required.
# Usage: ./system_update.sh

set -euo pipefail

LOG_FILE="/var/log/system_update.log"
# Use writable log location if we don't have permission to write to /var/log
if [ ! -w "/var/log" ]; then
	LOG_FILE="/tmp/system_update.log"
	echo "Warning: Cannot write to /var/log, using $LOG_FILE instead"
fi
exec &> >(tee -a "$LOG_FILE")

echo "Starting system update at $(date)"

echo "--> Updating package lists..."
sudo apt-get update

echo "--> Upgrading packages..."
sudo apt-get full-upgrade -y

echo "--> Removing unused packages..."
sudo apt-get autoremove -y

echo "--> Cleaning up local repository..."
sudo apt-get clean

echo "System update finished at $(date)"

if [ -f /var/run/reboot-required ]; then
    echo "A reboot is required."
fi
