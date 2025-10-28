#!/bin/bash
# clean_cache.sh - Clean system cache and temporary files
#
# This script performs system maintenance by cleaning up package caches and removing
# unused packages and temporary files. It is intended for use on Debian-based systems.
#
# Actions performed:
#   - Removes packages that were automatically installed to satisfy dependencies for other packages and are now no longer needed (autoremove).
#   - Cleans up the local repository of retrieved package files (autoclean and clean).
#   - Deletes all files in the /tmp directory.
#
# Usage:
#   ./clean_cache.sh
#
# Requirements:
#   - Must be run with sufficient privileges (sudo may be required).
#
# Note:
#   Use with caution, as deleting files from /tmp may affect running applications.
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-28
# Description: Cleans apt cache and removes unused packages and temporary files.
# Usage: ./cli.sh clean_cache

set -euo pipefail

sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get clean
find /tmp -mindepth 1 -exec rm -rf -- {} +
