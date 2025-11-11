#!/usr/bin/env bash
# =============================================================================
# test_mcp_local.sh - Local MCP Protocol Compliance Test Harness
# =============================================================================
#
# Description:
#   This script runs protocol-level tests for the Parrot MCP Server to validate
#   MCP message handling, logging behavior, and server lifecycle management.
#
# Usage:
#   ./test_mcp_local.sh [OPTIONS]
#
# Options:
#   -h, --help     Show this help message and exit
#   -v, --verbose  Enable verbose output for debugging
#   -d, --debug    Enable debug mode with detailed logging
#
# Environment Variables:
#   LOG_DIR        Directory for log files (default: ./logs)
#   IPC_DIR        Directory for IPC files (default: /tmp)
#   SCRIPT_DIR     Override script directory detection
#
# Requirements:
#   - start_mcp_server.sh must be present and executable
#   - stop_mcp_server.sh must be present and executable
#   - Write permissions to LOG_DIR and IPC_DIR
#
# Exit Codes:
#   0 - All tests passed
#   1 - Test failures or errors occurred
#   2 - Missing dependencies or setup issues
#
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION AND PATH RESOLUTION
# =============================================================================

# Resolve script directory using absolute path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up directories with validation
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
IPC_DIR="${IPC_DIR:-/tmp}"

# Define absolute paths to dependencies
START_SERVER_SCRIPT="${SCRIPT_DIR}/start_mcp_server.sh"
STOP_SERVER_SCRIPT="${SCRIPT_DIR}/stop_mcp_server.sh"

# Test configuration
TEST_TIMEOUT=5
VERBOSE=false
DEBUG=false

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Display usage information
show_help() {
    sed -n '2,33p' "$0" | sed 's/^# //g; s/^#$//g'
    exit 0
}

# Log messages with timestamp
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}"
}

# Log info messages
log_info() {
    log_message "INFO" "$@"
}

# Log error messages
log_error() {
    log_message "ERROR" "$@" >&2
}

# Log debug messages (only if DEBUG is enabled)
log_debug() {
    if [ "$DEBUG" = true ] || [ "$VERBOSE" = true ]; then
        log_message "DEBUG" "$@"
    fi
}

# Validate that a file exists and is executable
validate_executable() {
    local file="$1"
    local name="$2"
    
    if [ ! -f "$file" ]; then
        log_error "Missing required script: ${name} (${file})"
        log_error "Expected location: ${file}"
        return 1
    fi
    
    if [ ! -x "$file" ]; then
        log_error "Script is not executable: ${name} (${file})"
        log_error "Run: chmod +x ${file}"
        return 1
    fi
    
    log_debug "Validated ${name}: ${file}"
    return 0
}

# Validate and create directory if needed
validate_directory() {
    local dir="$1"
    local name="$2"
    
    if [ ! -d "$dir" ]; then
        log_debug "Creating ${name}: ${dir}"
        if ! mkdir -p "$dir"; then
            log_error "Failed to create ${name}: ${dir}"
            return 1
        fi
    fi
    
    if [ ! -w "$dir" ]; then
        log_error "${name} is not writable: ${dir}"
        return 1
    fi
    
    log_debug "Validated ${name}: ${dir}"
    return 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            VERBOSE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 2
            ;;
    esac
done

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_info "Starting MCP Server Test Harness"
log_debug "Script directory: ${SCRIPT_DIR}"
log_debug "Log directory: ${LOG_DIR}"
log_debug "IPC directory: ${IPC_DIR}"

# Validate required scripts exist and are executable
if ! validate_executable "$START_SERVER_SCRIPT" "start_mcp_server.sh"; then
    log_error "Cannot proceed without start_mcp_server.sh"
    exit 2
fi

if ! validate_executable "$STOP_SERVER_SCRIPT" "stop_mcp_server.sh"; then
    log_error "Cannot proceed without stop_mcp_server.sh"
    exit 2
fi

# Validate directories
if ! validate_directory "$LOG_DIR" "log directory"; then
    log_error "Cannot proceed without writable log directory"
    exit 2
fi

if ! validate_directory "$IPC_DIR" "IPC directory"; then
    log_error "Cannot proceed without writable IPC directory"
    exit 2
fi

# Define test file paths
MCP_INPUT_FILE="${IPC_DIR}/mcp_in.json"
MCP_BAD_FILE="${IPC_DIR}/mcp_bad.json"
LOG_FILE="${LOG_DIR}/parrot.log"

# Clean up any leftover test files from previous runs
log_debug "Cleaning up previous test artifacts"
rm -f "$MCP_INPUT_FILE" "$MCP_BAD_FILE" 2>/dev/null || true

# =============================================================================
# TEST EXECUTION
# =============================================================================

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

# Start the MCP server
log_info "Starting MCP server..."
if ! "$START_SERVER_SCRIPT"; then
    log_error "Failed to execute start_mcp_server.sh"
    exit 1
fi

# Read the actual server PID from the PID file
PID_FILE_PATH="${LOG_DIR}/mcp_server.pid"
if [ -f "$PID_FILE_PATH" ]; then
    SERVER_PID=$(cat "$PID_FILE_PATH")
    log_debug "Server process PID from file: ${SERVER_PID}"
    
    # Verify server process is running
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        log_error "Server process not running (PID: ${SERVER_PID})"
        exit 1
    fi
else
    log_error "PID file not found: ${PID_FILE_PATH}"
    exit 1
fi

# Wait for server to initialize
log_debug "Waiting ${TEST_TIMEOUT} seconds for server initialization..."
sleep "$TEST_TIMEOUT"

# Test 1: Send valid MCP message
log_info "[TEST 1] Sending valid MCP message..."
echo '{"type":"mcp_message","content":"ping"}' > "$MCP_INPUT_FILE"
log_debug "Created test file: ${MCP_INPUT_FILE}"

# Give server time to process
sleep 1

# Test 2: Send malformed MCP message
log_info "[TEST 2] Sending malformed MCP message..."
echo '{"type":"mcp_message",' > "$MCP_BAD_FILE"
log_debug "Created test file: ${MCP_BAD_FILE}"

# Give server time to process
sleep 1

# =============================================================================
# RESULT VALIDATION
# =============================================================================

log_info "Validating test results..."

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    log_error "Log file not found: ${LOG_FILE}"
    log_error "Server may not have started correctly"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    log_debug "Log file found: ${LOG_FILE}"
    
    # Validate Test 1: Check for valid message processing
    if grep -qi 'ping' "$LOG_FILE"; then
        log_info "[PASS] Valid MCP message processed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "[FAIL] Valid MCP message not found in logs"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Validate Test 2: Check for error logging on malformed message
    if grep -qi 'error' "$LOG_FILE"; then
        log_info "[PASS] Malformed MCP message error logged"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "[FAIL] Malformed MCP message error not found in logs"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi

# =============================================================================
# CLEANUP
# =============================================================================

log_info "Cleaning up test environment..."

# Stop the server using the stop script
log_debug "Executing stop script: ${STOP_SERVER_SCRIPT}"
if "$STOP_SERVER_SCRIPT"; then
    log_debug "Server stopped successfully via stop script"
else
    log_error "Stop script failed, attempting manual cleanup"
fi

# Ensure server process is terminated
if kill "$SERVER_PID" 2>/dev/null; then
    log_debug "Killed server process: ${SERVER_PID}"
else
    log_debug "Server process already terminated: ${SERVER_PID}"
fi

# Clean up test files
log_debug "Removing test files"
rm -f "$MCP_INPUT_FILE" "$MCP_BAD_FILE" 2>/dev/null || true

# =============================================================================
# TEST SUMMARY
# =============================================================================

log_info "========================================="
log_info "Test Summary"
log_info "========================================="
log_info "Tests Passed: ${TESTS_PASSED}"
log_info "Tests Failed: ${TESTS_FAILED}"
log_info "========================================="

# Exit with appropriate code
if [ "$TESTS_FAILED" -gt 0 ]; then
    log_error "Test suite FAILED"
    exit 1
else
    log_info "Test suite PASSED"
    exit 0
fi
