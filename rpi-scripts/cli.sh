
#!/bin/bash
# Central CLI tool for Raspberry Pi 5 scripts
# Author: Canstralian
# Usage: ./cli.sh <script> [args]

set -euo pipefail

SCRIPTS_DIR="$(dirname "$0")/scripts"
LOG_FILE="$(dirname "$0")/cli_error.log"

log_error() {
	local msg="$1"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

ascii_art() {
cat <<'EOF'
 ____            _     _     _      _     _     _
|  _ \ ___  __ _(_)___| |__ | | ___| |__ (_)___| |_
| |_) / _ \/ _` | / __| '_ \| |/ _ \ '_ \| / __| __|
|  _ <  __/ (_| | \__ \ | | | |  __/ |_) | \__ \ |_
|_| \_\___|\__, |_|___/_| |_|_|\___|_.__/|_|___/\__|
		   |___/
EOF
}

list_scripts() {
	for f in "$SCRIPTS_DIR"/*.sh; do
		[ -e "$f" ] || continue
		echo "  $(basename "$f" .sh)"
	done
}

show_help() {
	echo "Usage: $0 <script> [args]"
	echo "       $0 --help | -h"
	echo
	echo "If no script is provided, an interactive menu will be shown."
	echo "Available scripts:"
	list_scripts
}

validate_script_name() {
	# Only allow alphanumeric, underscore, and dash
	[[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

menu() {
	while true; do
		ascii_art
		echo
		echo "Welcome to the Raspberry Pi 5 CLI Tool!"
		echo "-------------------------------------"
		echo "Available scripts:"
		list_scripts
		echo "-------------------------------------"
		echo "Enter the script name to run, or 'q' to quit:"
		read -r choice
		if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
			echo "Goodbye!"
			exit 0
		fi
		if [ -z "$choice" ]; then
			echo "No script selected."
			continue
		fi
		if ! validate_script_name "$choice"; then
			echo "Invalid script name. Only letters, numbers, dash, and underscore allowed."
			log_error "Invalid script name input: $choice"
			continue
		fi
		SCRIPT="$SCRIPTS_DIR/$choice.sh"
		if [ -x "$SCRIPT" ]; then
			echo "Enter arguments for $choice (or press Enter for none):"
			read -r args
			if [ -n "$args" ]; then
				# shellcheck disable=SC2086
				"$SCRIPT" $args || { log_error "Script '$choice' exited with error code $?"; echo "[ERROR] Script '$choice' exited with error code $?"; }
			else
				"$SCRIPT" || { log_error "Script '$choice' exited with error code $?"; echo "[ERROR] Script '$choice' exited with error code $?"; }
			fi
		else
			echo "Script '$choice' not found or not executable."
			log_error "Script '$choice' not found or not executable."
		fi
		echo
		read -p "Press Enter to return to menu..." _
	done
}

main() {
	if [ $# -eq 0 ]; then
		menu
		exit 0
	fi
	case "$1" in
		--help|-h)
			show_help
			exit 0
			;;
	esac
	if ! validate_script_name "$1"; then
		echo "Invalid script name. Only letters, numbers, dash, and underscore allowed."
		log_error "Invalid script name input: $1"
		exit 3
	fi
	SCRIPT_NAME="$1"
	SCRIPT="$SCRIPTS_DIR/$1.sh"
	shift
	if [ -x "$SCRIPT" ]; then
		"$SCRIPT" "$@" || { log_error "Script '$SCRIPT_NAME' exited with error code $?"; echo "[ERROR] Script '$SCRIPT_NAME' exited with error code $?"; }
	else
		echo "Script '$SCRIPT_NAME' not found or not executable."
		log_error "Script '$SCRIPT_NAME' not found or not executable."
		echo "Falling back to menu."
		menu
	fi
}

# Trap unexpected errors and log them
trap 'ret=$?; if [ $ret -ne 0 ] && [ $ret -ne 2 ] && [ $ret -ne 130 ]; then log_error "Unexpected error (exit code $ret) in cli.sh"; echo "\n[ERROR] An unexpected error occurred. Exiting."; fi' EXIT

main "$@"
