#!/usr/bin/env bash
# openvas_scan.sh - OpenVAS vulnerability scanning integration
# Author: Canstralian
# Description: Performs vulnerability scans using OpenVAS/GVM and manages scan results
# Usage: ./openvas_scan.sh [--target TARGET] [--profile PROFILE] [--report-format FORMAT]

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

# Set script-specific log file (used by common_config.sh logging functions)
# shellcheck disable=SC2034
PARROT_CURRENT_LOG="${PARROT_LOG_DIR}/openvas_scan.log"

# ============================================================================
# CONFIGURATION
# ============================================================================

# OpenVAS/GVM Configuration
OPENVAS_HOST="${OPENVAS_HOST:-127.0.0.1}"
OPENVAS_PORT="${OPENVAS_PORT:-9390}"
OPENVAS_USER="${OPENVAS_USER:-admin}"
OPENVAS_PASSWORD_FILE="${OPENVAS_PASSWORD_FILE:-${PARROT_BASE_DIR}/.openvas_password}"
OPENVAS_TIMEOUT="${OPENVAS_TIMEOUT:-3600}"

# Scan Configuration
DEFAULT_TARGET="${DEFAULT_TARGET:-127.0.0.1}"
DEFAULT_PROFILE="${DEFAULT_PROFILE:-Full and fast}"
DEFAULT_REPORT_FORMAT="${DEFAULT_REPORT_FORMAT:-PDF}"

# Output Configuration
SCAN_RESULTS_DIR="${SCAN_RESULTS_DIR:-${PARROT_BASE_DIR}/scan_results}"
REPORT_RETENTION_DAYS="${REPORT_RETENTION_DAYS:-90}"

# ============================================================================
# UTILITY FUNCTIONS - SECURE PASSWORD MANAGEMENT
# ============================================================================

# Global variable to cache the password (will be unset on exit)
OPENVAS_PASSWORD=""

# Securely read and cache the OpenVAS password from file
# This function reads the password file only once and stores it in memory
# Implements proper validation and error handling
read_openvas_password() {
	# If password is already cached, return success
	if [ -n "$OPENVAS_PASSWORD" ]; then
		parrot_debug "Using cached OpenVAS password"
		return 0
	fi

	# Validate password file exists
	if [ ! -f "$OPENVAS_PASSWORD_FILE" ]; then
		parrot_error "OpenVAS password file not found: $OPENVAS_PASSWORD_FILE"
		parrot_error "Please create the password file with: echo 'your_password' > $OPENVAS_PASSWORD_FILE && chmod 600 $OPENVAS_PASSWORD_FILE"
		return 1
	fi

	# Validate file permissions (should be 600 or stricter)
	local perms
	perms=$(stat -c "%a" "$OPENVAS_PASSWORD_FILE" 2>/dev/null || stat -f "%Lp" "$OPENVAS_PASSWORD_FILE" 2>/dev/null)

	if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
		parrot_error "Insecure permissions on password file: $perms (should be 600 or 400)"
		parrot_error "Fix with: chmod 600 $OPENVAS_PASSWORD_FILE"
		return 1
	fi

	# Read password from file (only once!)
	OPENVAS_PASSWORD=$(head -n 1 "$OPENVAS_PASSWORD_FILE")

	# Validate password is not empty
	if [ -z "$OPENVAS_PASSWORD" ]; then
		parrot_error "OpenVAS password file is empty: $OPENVAS_PASSWORD_FILE"
		return 1
	fi

	# Validate password length and format
	if [ ${#OPENVAS_PASSWORD} -lt 8 ]; then
		parrot_error "OpenVAS password is too short (minimum 8 characters)"
		return 1
	fi

	parrot_debug "Successfully loaded OpenVAS password from file"
	return 0
}

# Clean up password from memory on exit
cleanup_password() {
	if [ -n "$OPENVAS_PASSWORD" ]; then
		# Overwrite password in memory before unsetting
		OPENVAS_PASSWORD=$(printf '%*s' ${#OPENVAS_PASSWORD} | tr ' ' '0')
		unset OPENVAS_PASSWORD
		parrot_debug "OpenVAS password cleared from memory"
	fi
}

# Register cleanup function to run on exit
trap cleanup_password EXIT INT TERM

# ============================================================================
# OPENVAS/GVM INTEGRATION FUNCTIONS
# ============================================================================

# Authenticate with OpenVAS/GVM
openvas_authenticate() {
	parrot_info "Authenticating with OpenVAS at ${OPENVAS_HOST}:${OPENVAS_PORT}"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	# Use gvm-cli or omp command to authenticate (simulated for this example)
	# In a real implementation, this would call gvm-cli with authentication
	if parrot_command_exists "gvm-cli"; then
		# Using cached password - NO FILE I/O HERE
		parrot_debug "Attempting authentication with username: $OPENVAS_USER"
		# Actual command would be: echo "$OPENVAS_PASSWORD" | gvm-cli --gmp-username "$OPENVAS_USER" ...
		parrot_info "Authentication successful (simulated)"
		return 0
	else
		parrot_warn "gvm-cli not found, running in simulation mode"
		return 0
	fi
}

# Create a new scan target
openvas_create_target() {
	local target_name="$1"
	local target_hosts="$2"

	parrot_info "Creating scan target: $target_name ($target_hosts)"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	# Use cached password - NO FILE I/O HERE
	if parrot_command_exists "gvm-cli"; then
		parrot_debug "Creating target with credentials"
		# Actual GVM command would use $OPENVAS_PASSWORD from memory
		parrot_info "Target created successfully (simulated)"
		return 0
	else
		parrot_info "Target creation simulated (gvm-cli not available)"
		return 0
	fi
}

# Create a new scan task
openvas_create_task() {
	local task_name="$1"
	local target_id="$2"
	local scan_profile="$3"

	parrot_info "Creating scan task: $task_name with profile '$scan_profile'"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	# Use cached password - NO FILE I/O HERE
	if parrot_command_exists "gvm-cli"; then
		parrot_debug "Creating task with profile: $scan_profile"
		# Actual GVM command would use $OPENVAS_PASSWORD from memory
		parrot_info "Task created successfully (simulated)"
		return 0
	else
		parrot_info "Task creation simulated (gvm-cli not available)"
		return 0
	fi
}

# Start a scan task
openvas_start_scan() {
	local task_id="$1"

	parrot_info "Starting scan task: $task_id"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	# Use cached password - NO FILE I/O HERE
	if parrot_command_exists "gvm-cli"; then
		parrot_debug "Starting scan task"
		# Actual GVM command would use $OPENVAS_PASSWORD from memory
		parrot_info "Scan started successfully (simulated)"
		return 0
	else
		parrot_info "Scan start simulated (gvm-cli not available)"
		return 0
	fi
}

# Monitor scan progress
openvas_monitor_scan() {
	local task_id="$1"

	parrot_info "Monitoring scan progress for task: $task_id"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	local progress=0
	while [ "$progress" -lt 100 ]; do
		# Use cached password - NO FILE I/O HERE
		if parrot_command_exists "gvm-cli"; then
			# Actual GVM command would use $OPENVAS_PASSWORD from memory
			progress=$((progress + 20))
			parrot_debug "Scan progress: ${progress}%"
			sleep 2
		else
			parrot_info "Scan monitoring simulated (gvm-cli not available)"
			break
		fi
	done

	parrot_info "Scan completed"
	return 0
}

# Get scan results
openvas_get_results() {
	local task_id="$1"

	parrot_info "Retrieving scan results for task: $task_id"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	# Use cached password - NO FILE I/O HERE
	if parrot_command_exists "gvm-cli"; then
		parrot_debug "Fetching results from OpenVAS"
		# Actual GVM command would use $OPENVAS_PASSWORD from memory
		parrot_info "Results retrieved successfully (simulated)"
		return 0
	else
		parrot_info "Results retrieval simulated (gvm-cli not available)"
		return 0
	fi
}

# Generate scan report
openvas_generate_report() {
	local task_id="$1"
	local format="$2"
	local output_file="$3"

	parrot_info "Generating ${format} report for task: $task_id"

	# Ensure password is loaded
	if ! read_openvas_password; then
		return 1
	fi

	# Ensure output directory exists
	local output_dir
	output_dir=$(dirname "$output_file")
	if [ ! -d "$output_dir" ]; then
		mkdir -p "$output_dir" || {
			parrot_error "Failed to create output directory: $output_dir"
			return 1
		}
	fi

	# Use cached password - NO FILE I/O HERE (except for output file)
	if parrot_command_exists "gvm-cli"; then
		parrot_debug "Generating report in format: $format"
		# Actual GVM command would use $OPENVAS_PASSWORD from memory
		echo "Simulated OpenVAS Scan Report - $(date)" >"$output_file"
		parrot_info "Report saved to: $output_file"
		return 0
	else
		# Create a simulated report
		cat >"$output_file" <<EOF
OpenVAS Vulnerability Scan Report (Simulated)
Generated: $(date)
Task ID: $task_id
Format: $format
Status: Completed

This is a simulated scan report for demonstration purposes.
In a real deployment, this would contain actual vulnerability findings.
EOF
		parrot_info "Simulated report saved to: $output_file"
		return 0
	fi
}

# Clean up old scan reports
openvas_cleanup_old_reports() {
	parrot_info "Cleaning up scan reports older than ${REPORT_RETENTION_DAYS} days"

	if [ ! -d "$SCAN_RESULTS_DIR" ]; then
		parrot_debug "Scan results directory does not exist: $SCAN_RESULTS_DIR"
		return 0
	fi

	local deleted_count=0
	while IFS= read -r -d '' file; do
		rm -f "$file"
		deleted_count=$((deleted_count + 1))
		parrot_debug "Deleted old report: $file"
	done < <(find "$SCAN_RESULTS_DIR" -type f -mtime +"$REPORT_RETENTION_DAYS" -print0 2>/dev/null)

	if [ "$deleted_count" -gt 0 ]; then
		parrot_info "Cleaned up $deleted_count old report(s)"
	else
		parrot_info "No old reports to clean up"
	fi

	return 0
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

# Default values
TARGET="$DEFAULT_TARGET"
PROFILE="$DEFAULT_PROFILE"
REPORT_FORMAT="$DEFAULT_REPORT_FORMAT"
CLEANUP_OLD=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	--target)
		if [ -z "${2:-}" ]; then
			parrot_error "Missing value for --target"
			exit 1
		fi
		TARGET="$2"
		shift 2
		;;
	--profile)
		if [ -z "${2:-}" ]; then
			parrot_error "Missing value for --profile"
			exit 1
		fi
		PROFILE="$2"
		shift 2
		;;
	--report-format)
		if [ -z "${2:-}" ]; then
			parrot_error "Missing value for --report-format"
			exit 1
		fi
		REPORT_FORMAT="$2"
		shift 2
		;;
	--cleanup-old)
		CLEANUP_OLD=true
		shift
		;;
	--help | -h)
		cat <<EOF
Usage: $0 [OPTIONS]

OpenVAS vulnerability scanning integration for Parrot MCP Server

Options:
  --target TARGET            Target host or network to scan (default: $DEFAULT_TARGET)
  --profile PROFILE          Scan profile to use (default: $DEFAULT_PROFILE)
  --report-format FORMAT     Report format (PDF, XML, HTML) (default: $DEFAULT_REPORT_FORMAT)
  --cleanup-old              Clean up reports older than ${REPORT_RETENTION_DAYS} days
  --help, -h                 Show this help message

Environment variables (from config.env):
  OPENVAS_HOST               OpenVAS server host (currently: $OPENVAS_HOST)
  OPENVAS_PORT               OpenVAS server port (currently: $OPENVAS_PORT)
  OPENVAS_USER               OpenVAS username (currently: $OPENVAS_USER)
  OPENVAS_PASSWORD_FILE      Path to password file (currently: $OPENVAS_PASSWORD_FILE)
  SCAN_RESULTS_DIR           Directory for scan results (currently: $SCAN_RESULTS_DIR)

Security Note:
  The password file should have permissions 600 and contain only the password.
  Create it with: echo 'your_password' > $OPENVAS_PASSWORD_FILE && chmod 600 $OPENVAS_PASSWORD_FILE

EOF
		exit 0
		;;
	*)
		parrot_error "Unknown option: $1"
		echo "Use --help for usage information"
		exit 1
		;;
	esac
done

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
	parrot_info "Starting OpenVAS vulnerability scan"
	parrot_info "Configuration: target=$TARGET, profile='$PROFILE', format=$REPORT_FORMAT"

	# Initialize results directory
	if [ ! -d "$SCAN_RESULTS_DIR" ]; then
		mkdir -p "$SCAN_RESULTS_DIR" || {
			parrot_error "Failed to create scan results directory: $SCAN_RESULTS_DIR"
			return 1
		}
		chmod 700 "$SCAN_RESULTS_DIR"
	fi

	# Perform cleanup if requested
	if [ "$CLEANUP_OLD" = true ]; then
		if ! openvas_cleanup_old_reports; then
			parrot_warn "Failed to clean up old reports, continuing with scan"
		fi
	fi

	# Authenticate with OpenVAS (password read happens here, cached for subsequent calls)
	if ! openvas_authenticate; then
		parrot_error "Failed to authenticate with OpenVAS"
		return 1
	fi

	# Create scan target
	local target_id
	target_id="target_$(date +%s)"
	if ! openvas_create_target "$TARGET" "$TARGET"; then
		parrot_error "Failed to create scan target"
		return 1
	fi

	# Create scan task
	local task_id
	task_id="task_$(date +%Y%m%d_%H%M%S)"
	if ! openvas_create_task "Scan_${TARGET}_$(date +%Y%m%d)" "$target_id" "$PROFILE"; then
		parrot_error "Failed to create scan task"
		return 1
	fi

	# Start the scan
	if ! openvas_start_scan "$task_id"; then
		parrot_error "Failed to start scan"
		return 1
	fi

	# Monitor scan progress
	if ! openvas_monitor_scan "$task_id"; then
		parrot_error "Failed to monitor scan"
		return 1
	fi

	# Get results
	if ! openvas_get_results "$task_id"; then
		parrot_error "Failed to retrieve scan results"
		return 1
	fi

	# Generate report
	local report_file
	report_file="${SCAN_RESULTS_DIR}/scan_${TARGET}_$(date +%Y%m%d_%H%M%S).${REPORT_FORMAT,,}"
	if ! openvas_generate_report "$task_id" "$REPORT_FORMAT" "$report_file"; then
		parrot_error "Failed to generate report"
		return 1
	fi

	parrot_info "OpenVAS scan completed successfully"
	parrot_info "Report available at: $report_file"

	# Send notification if configured
	if [ -n "$PARROT_NOTIFY_EMAIL" ]; then
		parrot_send_notification "OpenVAS Scan Completed" \
			"Vulnerability scan completed for target: $TARGET\nReport: $report_file"
	fi

	return 0
}

# Run main function
main
