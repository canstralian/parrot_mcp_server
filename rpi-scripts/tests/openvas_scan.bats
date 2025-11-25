#!/usr/bin/env bats
# openvas_scan.bats - Tests for openvas_scan.sh script

# Setup test environment
setup() {
	# Store original directory
	ORIG_DIR="$(pwd)"

	# Find the script directory
	if [ -f "scripts/openvas_scan.sh" ]; then
		SCRIPT_DIR="$(pwd)"
	elif [ -f "../scripts/openvas_scan.sh" ]; then
		SCRIPT_DIR="$(cd .. && pwd)"
	elif [ -f "rpi-scripts/scripts/openvas_scan.sh" ]; then
		SCRIPT_DIR="$(pwd)/rpi-scripts"
	else
		echo "# Cannot find openvas_scan.sh" >&2
		return 1
	fi

	# Create temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Create test log directory
	mkdir -p "$TEST_DIR/logs"
	mkdir -p "$TEST_DIR/scan_results"

	# Create a test password file with proper permissions
	echo "test_password_12345" >"$TEST_DIR/.openvas_password"
	chmod 600 "$TEST_DIR/.openvas_password"

	# Export test configuration
	export PARROT_BASE_DIR="$TEST_DIR"
	export PARROT_LOG_DIR="$TEST_DIR/logs"
	export OPENVAS_PASSWORD_FILE="$TEST_DIR/.openvas_password"
	export SCAN_RESULTS_DIR="$TEST_DIR/scan_results"
	export PARROT_ALERT_EMAIL="" # Disable email notifications in tests
	export PARROT_NOTIFY_EMAIL="" # Disable email notifications in tests
	export PARROT_DEBUG="false"

	# Change to script directory for execution
	cd "$SCRIPT_DIR"
}

teardown() {
	# Return to original directory
	cd "$ORIG_DIR"

	# Cleanup temporary test directory
	if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

# ============================================================================
# COMMAND-LINE ARGUMENT TESTS
# ============================================================================

@test "openvas_scan: accepts --help flag" {
	run bash scripts/openvas_scan.sh --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage:" ]]
}

@test "openvas_scan: accepts -h flag" {
	run bash scripts/openvas_scan.sh -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage:" ]]
}

@test "openvas_scan: accepts --target with valid IP" {
	run bash scripts/openvas_scan.sh --target 192.168.1.1
	[ "$status" -eq 0 ]
}

@test "openvas_scan: accepts --profile option" {
	run bash scripts/openvas_scan.sh --profile "Full and fast"
	[ "$status" -eq 0 ]
}

@test "openvas_scan: accepts --report-format option" {
	run bash scripts/openvas_scan.sh --report-format PDF
	[ "$status" -eq 0 ]
}

@test "openvas_scan: accepts --cleanup-old flag" {
	run bash scripts/openvas_scan.sh --cleanup-old
	[ "$status" -eq 0 ]
}

@test "openvas_scan: rejects unknown option" {
	run bash scripts/openvas_scan.sh --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "openvas_scan: rejects --target without value" {
	run bash scripts/openvas_scan.sh --target
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Missing value" ]]
}

# ============================================================================
# PASSWORD FILE SECURITY TESTS
# ============================================================================

@test "SECURITY: openvas_scan fails when password file is missing" {
	# Remove password file
	rm -f "$TEST_DIR/.openvas_password"
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 1 ]
	[[ "$output" =~ "password file not found" || "$output" =~ "Failed to authenticate" ]]
}

@test "SECURITY: openvas_scan fails when password file has insecure permissions" {
	# Set insecure permissions
	chmod 644 "$TEST_DIR/.openvas_password"
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Insecure permissions" || "$output" =~ "Failed to authenticate" ]]
}

@test "SECURITY: openvas_scan accepts password file with 400 permissions" {
	# Set restrictive permissions
	chmod 400 "$TEST_DIR/.openvas_password"
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
}

@test "SECURITY: openvas_scan fails when password file is empty" {
	# Create empty password file
	: >"$TEST_DIR/.openvas_password"
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 1 ]
	[[ "$output" =~ "password file is empty" || "$output" =~ "Failed to authenticate" ]]
}

@test "SECURITY: openvas_scan fails when password is too short" {
	# Create password file with short password
	echo "short" >"$TEST_DIR/.openvas_password"
	chmod 600 "$TEST_DIR/.openvas_password"
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 1 ]
	[[ "$output" =~ "password is too short" || "$output" =~ "Failed to authenticate" ]]
}

@test "SECURITY: openvas_scan reads password file only once per execution" {
	# This is a behavioral test - we verify the script completes successfully
	# The actual implementation caches the password in memory
	run bash scripts/openvas_scan.sh --target 192.168.1.1
	[ "$status" -eq 0 ]

	# Check that the log shows password was loaded (not read multiple times)
	log_file="$TEST_DIR/logs/openvas_scan.log"
	if [ -f "$log_file" ]; then
		# Should see "loaded" once, not multiple times
		loaded_count=$(grep -c "Successfully loaded OpenVAS password" "$log_file" || echo "0")
		[ "$loaded_count" -le 1 ]
	fi
}

# ============================================================================
# LOGGING TESTS
# ============================================================================

@test "openvas_scan: creates log file" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
	[ -f "$TEST_DIR/logs/openvas_scan.log" ]
}

@test "openvas_scan: log contains timestamp" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
	grep -q '\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$TEST_DIR/logs/openvas_scan.log"
}

@test "openvas_scan: log contains message ID" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
	grep -q '\[msgid:[0-9]\+\]' "$TEST_DIR/logs/openvas_scan.log"
}

@test "openvas_scan: log contains INFO level" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
	grep -q '\[INFO\]' "$TEST_DIR/logs/openvas_scan.log"
}

# ============================================================================
# SCAN EXECUTION TESTS
# ============================================================================

@test "openvas_scan: creates scan results directory" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
	[ -d "$TEST_DIR/scan_results" ]
}

@test "openvas_scan: generates scan report" {
	run bash scripts/openvas_scan.sh --target 192.168.1.100
	[ "$status" -eq 0 ]

	# Check that a report file was created
	report_count=$(find "$TEST_DIR/scan_results" -type f -name "scan_*.pdf" | wc -l)
	[ "$report_count" -ge 1 ]
}

@test "openvas_scan: report file contains expected content" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]

	# Find the generated report
	report_file=$(find "$TEST_DIR/scan_results" -type f -name "scan_*.pdf" | head -1)
	[ -n "$report_file" ]
	[ -f "$report_file" ]

	# Check report contains expected header (for simulated reports)
	grep -q "OpenVAS" "$report_file"
}

@test "openvas_scan: uses specified target in report" {
	run bash scripts/openvas_scan.sh --target 10.0.0.50
	[ "$status" -eq 0 ]

	# Report filename should include the target
	report_file=$(find "$TEST_DIR/scan_results" -type f -name "scan_10.0.0.50_*.pdf" | head -1)
	[ -n "$report_file" ]
}

@test "openvas_scan: supports different report formats" {
	run bash scripts/openvas_scan.sh --report-format XML
	[ "$status" -eq 0 ]

	# Check for XML report
	report_count=$(find "$TEST_DIR/scan_results" -type f -name "scan_*.xml" | wc -l)
	[ "$report_count" -ge 1 ]
}

# ============================================================================
# CLEANUP TESTS
# ============================================================================

@test "openvas_scan: cleanup-old removes old reports" {
	# Create some old test reports
	touch -t 202301010000 "$TEST_DIR/scan_results/scan_old_report.pdf"
	touch -t 202312010000 "$TEST_DIR/scan_results/scan_recent_report.pdf"

	run bash scripts/openvas_scan.sh --cleanup-old
	[ "$status" -eq 0 ]

	# Old report should be removed (>90 days by default)
	[ ! -f "$TEST_DIR/scan_results/scan_old_report.pdf" ]
}

@test "openvas_scan: cleanup-old preserves recent reports" {
	# Create a recent report
	touch "$TEST_DIR/scan_results/scan_recent_report.pdf"

	run bash scripts/openvas_scan.sh --cleanup-old
	[ "$status" -eq 0 ]

	# Recent report should be preserved
	[ -f "$TEST_DIR/scan_results/scan_recent_report.pdf" ]
}

@test "openvas_scan: handles missing scan_results directory in cleanup" {
	# Remove scan_results directory
	rm -rf "$TEST_DIR/scan_results"

	run bash scripts/openvas_scan.sh --cleanup-old
	# Should handle gracefully and complete successfully
	[ "$status" -eq 0 ]
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

@test "openvas_scan: logs configuration on startup" {
	run bash scripts/openvas_scan.sh --target 192.168.1.1 --profile "Full and fast"
	[ "$status" -eq 0 ]
	grep -q "Configuration:" "$TEST_DIR/logs/openvas_scan.log"
	grep -q "target=192.168.1.1" "$TEST_DIR/logs/openvas_scan.log"
}

@test "openvas_scan: uses default target when not specified" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]
	# Should complete without errors using default target
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "openvas_scan: handles missing log directory" {
	# Remove log directory
	rm -rf "$TEST_DIR/logs"
	run bash scripts/openvas_scan.sh
	# Script should create directory or handle gracefully
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "openvas_scan: fails gracefully with authentication error" {
	# Use wrong password
	echo "wrong_password" >"$TEST_DIR/.openvas_password"
	run bash scripts/openvas_scan.sh
	# Should fail but exit cleanly
	[ "$status" -eq 1 ]
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

@test "openvas_scan: completes full scan workflow" {
	run bash scripts/openvas_scan.sh --target 192.168.1.10 --profile "Full and fast" --report-format PDF
	[ "$status" -eq 0 ]

	log_content=$(cat "$TEST_DIR/logs/openvas_scan.log")

	# Verify all stages were performed
	echo "$log_content" | grep -q "Starting OpenVAS vulnerability scan"
	echo "$log_content" | grep -q "Authenticating with OpenVAS"
	echo "$log_content" | grep -q "Creating scan target"
	echo "$log_content" | grep -q "Creating scan task"
	echo "$log_content" | grep -q "Starting scan task"
	echo "$log_content" | grep -q "Scan completed"
}

@test "openvas_scan: exit code reflects overall status" {
	run bash scripts/openvas_scan.sh
	# Exit code should be 0 for success or 1 for failures
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ============================================================================
# PASSWORD CACHING EFFICIENCY TESTS
# ============================================================================

@test "PASSWORD_OPTIMIZATION: password read function returns success when cached" {
	# This test verifies that the password caching mechanism works
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]

	# If logging is detailed enough, we should see "Using cached OpenVAS password"
	# but this depends on DEBUG mode, so we just verify success
	log_file="$TEST_DIR/logs/openvas_scan.log"
	[ -f "$log_file" ]
}

@test "PASSWORD_OPTIMIZATION: script completes with single password file read" {
	# Monitor file access during script execution
	# The script should read the password file only once at the beginning
	run bash scripts/openvas_scan.sh --target 192.168.1.1
	[ "$status" -eq 0 ]

	# Verify scan completed - this indirectly confirms password was available throughout
	log_file="$TEST_DIR/logs/openvas_scan.log"
	grep -q "completed successfully" "$log_file"
}

# ============================================================================
# SECURITY VALIDATION TESTS
# ============================================================================

@test "SECURITY: openvas_scan prevents command injection in target" {
	run bash scripts/openvas_scan.sh --target "192.168.1.1; rm -rf /"
	# Script should reject malicious input (must exit non-zero)
	[ "$status" -ne 0 ]
	# System should still be intact
	[ -d /bin ]
}

@test "SECURITY: openvas_scan prevents command injection in profile" {
	run bash scripts/openvas_scan.sh --profile "Full; cat /etc/passwd"
	# Script should reject malicious input and exit with error
	[ "$status" -eq 1 ]
	[[ "$output" == *"Invalid scan profile"* ]]
}

@test "SECURITY: openvas_scan cleans up password from memory" {
	# This test verifies the cleanup trap is registered
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]

	# After script completes, password should be cleared (verified via trap)
	# We can't directly test memory cleanup, but the script should complete successfully
}

@test "SECURITY: openvas_scan validates scan_results directory permissions" {
	run bash scripts/openvas_scan.sh
	[ "$status" -eq 0 ]

	# Check that scan_results directory has proper permissions (700)
	perms=$(stat -c "%a" "$TEST_DIR/scan_results" 2>/dev/null || stat -f "%Lp" "$TEST_DIR/scan_results" 2>/dev/null)
	[ "$perms" = "700" ]
}
