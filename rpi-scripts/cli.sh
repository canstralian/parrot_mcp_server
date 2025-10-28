#!/usr/bin/env bash
: '
cli.sh - Central CLI tool for Raspberry Pi 5 scripts

Author: Canstralian

Description:
	This script serves as a command-line interface (CLI) for managing and executing
	various Raspberry Pi 5 scripts located in a designated "scripts" directory.
	It provides both direct command execution and an interactive menu for script selection.

Features:
	- Lists available scripts in the "scripts" directory.
	- Validates script names to prevent unsafe execution.
	- Logs errors and unexpected events to a log file.
	- Displays ASCII art banner and usage instructions.
	- Supports both direct invocation and interactive menu mode.
	- Optionally hashes sensitive arguments before passing to scripts (demo purpose).
	- Handles and logs unexpected errors, with special handling for common exit codes.

Usage:
	./cli.sh <script> [args]
		Executes the specified script with optional arguments.

	./cli.sh --help | -h
		Displays help and usage information.

	./cli.sh
		Launches the interactive menu for script selection.

Functions:
	- log_error(msg): Logs error messages with timestamps to the log file.
	- ascii_art():   Displays an ASCII art banner.
	- list_scripts(): Lists all available scripts in the scripts directory.
	- show_help():   Prints usage instructions and available scripts.
	- validate_script_name(name): Validates script names for safety.
	- hash_arg(arg): Hashes an argument using sha256sum (demo).
	- menu():        Provides an interactive menu for script selection and execution.
	- main():        Main entry point; parses arguments and dispatches to appropriate mode.

Error Handling:
	- All errors are logged to a log file with timestamps.
	- Unexpected errors (excluding exit codes 0, 2, 130) are logged and reported to the user.

Directory Structure:
	- cli.sh (this script)
	- scripts/ (directory containing executable .sh scripts)
	- cli_error.log (error log file)

'
# Central CLI tool for Raspberry Pi 5 scripts
# Author: Canstralian
# Usage: ./cli.sh <script> [args]

SCRIPTS_DIR="$(dirname "$0")/scripts"
LOG_FILE="$(dirname "$0")/cli_error.log"

set -euo pipefail

log_error() {
	local msg="$1"
	local msgid
	msgid=$(date +%s%N)
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] [msgid:$msgid] $msg" >>"$LOG_FILE"
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
	[[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]
}

hash_arg() {
	# Hash an argument using sha256sum (for demonstration)
	echo -n "$1" | sha256sum | awk '{print $1}'
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
			echo "[ERROR] Invalid script name. Only letters, numbers, dash, and underscore allowed."
			log_error "Invalid script name input: $choice"
			continue
		fi
		SCRIPT="$SCRIPTS_DIR/$choice.sh"
		if [ -x "$SCRIPT" ]; then
			echo "Enter arguments for $choice (or press Enter for none):"
			read -r args
			# Optionally hash/salt sensitive arguments (example: hash first arg)
			if [ -n "$args" ]; then
				# shellcheck disable=SC2086
				set -- $args
				hashed_first_arg=$(hash_arg "$1")
				"$SCRIPT" "$hashed_first_arg" "${@:2}" || {
					log_error "Script '$choice' exited with error code $? (menu mode)"
					echo "[ERROR] Script '$choice' exited with error code $?"
				}
			else
				"$SCRIPT" || {
					log_error "Script '$choice' exited with error code $? (menu mode)"
					echo "[ERROR] Script '$choice' exited with error code $?"
				}
			fi
		else
			echo "[ERROR] Script '$choice' not found or not executable."
			log_error "Script '$choice' not found or not executable."
		fi
		echo
		read -r -p "Press Enter to return to menu..." _
	done
}

main() {
	if [ $# -eq 0 ]; then
		menu
		exit 0
	fi
	case "$1" in
	--help | -h)
		show_help
		exit 0
		;;
	esac

	# FIX 2 (Bug): Store the script name ($1) in a variable *before*
	# calling 'shift'. This prevents the error logs from using the
	# wrong variable (e.g., logging "Script 'arg1' failed" instead of
	# "Script 'my-script' failed").
	script_name="$1"

	if ! validate_script_name "$script_name"; then
		echo "[ERROR] Invalid script name. Only letters, numbers, dash, and underscore allowed."
		log_error "Invalid script name input: $script_name"
		exit 3
	fi
	SCRIPT="$SCRIPTS_DIR/$script_name.sh"
	shift
	if [ -x "$SCRIPT" ]; then
		# Use '$script_name' in the error log
		"$SCRIPT" "$@"
		status=$?
		if [ "$status" -ne 0 ]; then
			log_error "Script '$script_name' exited with error code $status (direct mode)"
			echo "[ERROR] Script '$script_name' exited with error code $status"
		fi
	else
		# Use '$script_name' in the error log
		echo "[ERROR] Script '$script_name' not found or not executable."
		log_error "Script '$script_name' not found or not executable."
		echo "Falling back to menu."
		menu
	fi
}

# Trap unexpected errors and log them.
# Exit codes 0 (success), 2 (usage error, e.g. from 'getopts'), and 130 (SIGINT/Ctrl-C) are considered "expected" and will not trigger error logging.
# All other exit codes are treated as unexpected and will be logged for auditability.
# shellcheck disable=SC2154
trap 'ret=$?; if [ "$ret" -ne 0 ] && [ "$ret" -ne 2 ] && [ "$ret" -ne 130 ]; then log_error "Unexpected error (exit code $ret) in cli.sh"; echo "\n[ERROR] An unexpected error occurred. Exiting."; fi' EXIT
