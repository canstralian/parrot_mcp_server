#!/bin/bash
# system_update.sh - Update and upgrade system packages
# Author: Canstralian
# Created: 2025-10-28
# Last Modified: 2025-10-28
# Description: Updates package lists and upgrades all packages on Raspberry Pi 5.
# Usage: ./system_update.sh

set -euo pipefail

sudo apt-get update && sudo apt-get full-upgrade -y
