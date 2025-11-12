# Error Handling and Validation Guide

This document describes the comprehensive error handling and validation system implemented in the Parrot MCP Server.

## Overview

The error handling system provides:
- **Standardized error responses** in JSON format
- **Consistent error codes** across the application
- **Input validation** for all user inputs and MCP messages
- **Retry logic** with exponential backoff
- **Circuit breaker pattern** for failing services
- **Request ID tracking** for auditability

## Error Codes

All error codes are defined in `error_handling.sh` and follow a consistent numbering scheme:

### Success (0)
- `PARROT_ERR_SUCCESS` (0) - Operation completed successfully

### Validation Errors (10-19)
- `PARROT_ERR_INVALID_INPUT` (10) - Generic invalid input
- `PARROT_ERR_INVALID_JSON` (11) - Invalid JSON syntax
- `PARROT_ERR_INVALID_TARGET` (12) - Invalid IP or hostname
- `PARROT_ERR_INVALID_PORT` (13) - Invalid port number
- `PARROT_ERR_INVALID_PARAMETER` (14) - Invalid parameter value
- `PARROT_ERR_MISSING_REQUIRED` (15) - Required field missing

### Tool Execution Errors (20-29)
- `PARROT_ERR_TOOL_FAILED` (20) - Tool execution failed
- `PARROT_ERR_TOOL_NOT_FOUND` (21) - Tool not found
- `PARROT_ERR_TOOL_TIMEOUT` (22) - Tool execution timeout
- `PARROT_ERR_TOOL_PERMISSION` (23) - Permission denied for tool

### System Errors (30-39)
- `PARROT_ERR_FILE_NOT_FOUND` (30) - File not found
- `PARROT_ERR_PERMISSION_DENIED` (31) - Permission denied
- `PARROT_ERR_DISK_FULL` (32) - Disk full
- `PARROT_ERR_OUT_OF_MEMORY` (33) - Out of memory

### Protocol Errors (40-49)
- `PARROT_ERR_PROTOCOL_VIOLATION` (40) - Protocol violation
- `PARROT_ERR_MESSAGE_TOO_LARGE` (41) - Message exceeds size limit
- `PARROT_ERR_INVALID_MESSAGE_TYPE` (42) - Invalid message type
- `PARROT_ERR_MALFORMED_MESSAGE` (43) - Malformed message structure

### Authentication/Authorization Errors (50-59)
- `PARROT_ERR_AUTH_FAILED` (50) - Authentication failed
- `PARROT_ERR_AUTH_REQUIRED` (51) - Authentication required
- `PARROT_ERR_INSUFFICIENT_PERMS` (52) - Insufficient permissions

### Network/Communication Errors (60-69)
- `PARROT_ERR_NETWORK_TIMEOUT` (60) - Network timeout
- `PARROT_ERR_CONNECTION_FAILED` (61) - Connection failed
- `PARROT_ERR_HOST_UNREACHABLE` (62) - Host unreachable

### General Errors (90-99)
- `PARROT_ERR_UNKNOWN` (90) - Unknown error
- `PARROT_ERR_INTERNAL` (91) - Internal server error
- `PARROT_ERR_NOT_IMPLEMENTED` (92) - Feature not implemented

## Error Response Format

All errors follow a standardized JSON format:

```json
{
  "error": {
    "code": "INVALID_INPUT",
    "exit_code": 10,
    "message": "Target parameter is required",
    "details": {
      "field": "target",
      "provided": null,
      "expected": "string (IP or hostname)"
    },
    "request_id": "req_1762927319_6020_30817",
    "timestamp": "2025-11-12T06:03:21Z"
  }
}
```

### Fields

- **code**: Human-readable error code (string)
- **exit_code**: Numeric error code for shell scripts (integer)
- **message**: User-friendly error message (string)
- **details**: Additional context about the error (object)
  - **field**: Name of the field with error
  - **provided**: Value that was provided
  - **expected**: Expected value or format
- **request_id**: Unique request identifier for tracking (string)
- **timestamp**: ISO 8601 timestamp in UTC (string)

## Using Error Handling in Scripts

### Load the Module

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load error handling
source "$(dirname "$0")/error_handling.sh"
```

### Handle Errors

```bash
# Check for error condition
if ! parrot_validate_target "$target"; then
    parrot_handle_error "$PARROT_ERR_INVALID_TARGET" \
        "Invalid target: $target" \
        "Expected IP address or hostname"
    exit "$PARROT_ERR_INVALID_TARGET"
fi
```

### Generate Error Responses

```bash
# Generate JSON error response
error_json=$(parrot_format_error_response \
    "$PARROT_ERR_MISSING_REQUIRED" \
    "Target parameter is required" \
    "target" \
    "null" \
    "string (IP or hostname)" \
    "req_123456")

echo "$error_json" > error_response.json
```

## Input Validation

The system provides comprehensive validation functions:

### IP Address Validation

```bash
# Validate IPv4 address
if parrot_validate_ipv4 "192.168.1.1"; then
    echo "Valid IP"
fi
```

### Hostname Validation

```bash
# Validate hostname (RFC 1123)
if parrot_validate_hostname "example.com"; then
    echo "Valid hostname"
fi
```

### Port Validation

```bash
# Validate single port
if parrot_validate_port "80"; then
    echo "Valid port"
fi

# Validate port range or list
if parrot_validate_port_range "80-443,8080"; then
    echo "Valid port specification"
fi
```

### Target Validation (IP or Hostname)

```bash
# Validate target accepts either IP or hostname
if parrot_validate_target "$user_input"; then
    echo "Valid target"
fi
```

### Target Sanitization

```bash
# Sanitize target to prevent command injection
safe_target=$(parrot_sanitize_target "$user_input")
# safe_target now contains only safe characters
```

### MCP Message Validation

```bash
# Validate MCP message structure and size
if parrot_validate_mcp_message "/tmp/mcp_in.json"; then
    echo "Valid MCP message"
else
    exit_code=$?
    echo "Validation failed with code: $exit_code"
fi
```

## Retry Logic

Execute commands with automatic retry and exponential backoff:

```bash
# Use default retry count from config (PARROT_RETRY_COUNT)
if parrot_execute_with_retry command arg1 arg2; then
    echo "Command succeeded"
else
    echo "Command failed after retries"
fi
```

The retry logic:
1. Attempts the command up to `PARROT_RETRY_COUNT` times (default: 3)
2. Waits `PARROT_RETRY_DELAY` seconds between attempts (default: 5)
3. Doubles the delay after each failure (exponential backoff)

## Timeout Handling

Execute commands with timeout:

```bash
# Execute with 30-second timeout
if parrot_execute_with_timeout 30 long_running_command; then
    echo "Command completed"
else
    exit_code=$?
    if [ "$exit_code" -eq "$PARROT_ERR_TOOL_TIMEOUT" ]; then
        echo "Command timed out"
    else
        echo "Command failed"
    fi
fi
```

## Circuit Breaker Pattern

The circuit breaker prevents cascading failures by tracking service health:

```bash
# Check if service is available
if parrot_circuit_breaker_check "external_api"; then
    # Service is available, proceed with call
    if call_external_api; then
        parrot_circuit_breaker_success "external_api"
    else
        parrot_circuit_breaker_failure "external_api"
    fi
else
    echo "Circuit breaker open, service unavailable"
    exit "$PARROT_ERR_CONNECTION_FAILED"
fi
```

### Circuit States

1. **CLOSED** (normal): All requests proceed normally
2. **OPEN** (failing): Requests are rejected immediately
3. **HALF_OPEN** (testing): One request is allowed to test recovery

### Configuration

- `PARROT_CIRCUIT_BREAKER_THRESHOLD`: Number of failures before opening (default: 5)
- `PARROT_CIRCUIT_BREAKER_TIMEOUT`: Seconds to wait before testing recovery (default: 60)
- `PARROT_CIRCUIT_BREAKER_DIR`: Directory for state files (default: /tmp/parrot_circuit_breaker)

## Request ID Tracking

Every operation generates a unique request ID for tracking:

```bash
# Generate request ID
request_id=$(parrot_generate_request_id)
# Output: req_1762927319_6020_30817

# Generate with custom prefix
request_id=$(parrot_generate_request_id "batch")
# Output: batch_1762927319_6020_30817
```

Request IDs are included in:
- Log messages
- Error responses
- MCP protocol responses

## Configuration

Error handling behavior is controlled by environment variables in `common_config.sh`:

### Validation
- `PARROT_VALIDATION_LEVEL`: STRICT (default) or RELAXED
- `PARROT_MAX_INPUT_SIZE`: Maximum input size in bytes (default: 1048576)

### Retry
- `PARROT_RETRY_COUNT`: Number of retry attempts (default: 3)
- `PARROT_RETRY_DELAY`: Initial delay between retries in seconds (default: 5)
- `PARROT_COMMAND_TIMEOUT`: Command timeout in seconds (default: 300)

### Circuit Breaker
- `PARROT_CIRCUIT_BREAKER_THRESHOLD`: Failures before opening (default: 5)
- `PARROT_CIRCUIT_BREAKER_TIMEOUT`: Timeout before testing recovery (default: 60)

### Logging
- `PARROT_LOG_LEVEL`: DEBUG, INFO (default), WARN, or ERROR
- `PARROT_DEBUG`: Set to true for verbose output

## Error Response Log

All error responses are logged to `${PARROT_LOG_DIR}/error_responses.log` for audit and analysis:

```bash
tail -f logs/error_responses.log
```

## Examples

### Complete Script with Error Handling

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"
source "${SCRIPT_DIR}/error_handling.sh"

# Parse arguments
if [ $# -lt 1 ]; then
    parrot_handle_error "$PARROT_ERR_MISSING_REQUIRED" \
        "Target parameter is required"
    exit "$PARROT_ERR_MISSING_REQUIRED"
fi

target="$1"

# Validate input
if ! parrot_validate_target "$target"; then
    error_json=$(parrot_format_error_response \
        "$PARROT_ERR_INVALID_TARGET" \
        "Invalid target: $target" \
        "target" \
        "$target" \
        "IP address or hostname")
    
    echo "$error_json" >&2
    exit "$PARROT_ERR_INVALID_TARGET"
fi

# Sanitize input
safe_target=$(parrot_sanitize_target "$target")

# Execute with retry and timeout
if parrot_execute_with_timeout 30 parrot_execute_with_retry ping -c 1 "$safe_target"; then
    parrot_info "Successfully pinged $safe_target"
    exit 0
else
    exit_code=$?
    parrot_handle_error "$exit_code" "Failed to ping $safe_target"
    exit "$exit_code"
fi
```

## Testing

Comprehensive tests are available in `tests/error_handling.bats`:

```bash
# Run error handling tests
bats tests/error_handling.bats

# Run all tests
bats tests/
```

## Best Practices

1. **Always validate user input** before processing
2. **Use appropriate error codes** for different failure types
3. **Include request IDs** in all log messages and responses
4. **Sanitize inputs** before passing to external commands
5. **Use retry logic** for transient failures
6. **Implement circuit breakers** for external service calls
7. **Log all errors** with sufficient context for debugging
8. **Return structured error responses** for API/protocol interactions
9. **Test error paths** thoroughly with edge cases
10. **Document error codes** and their meanings

## Migration Guide

### Updating Existing Scripts

1. Add error handling module:
   ```bash
   source "${SCRIPT_DIR}/error_handling.sh"
   ```

2. Replace manual validation with standard functions:
   ```bash
   # Before
   if [[ ! "$ip" =~ ^[0-9.]+$ ]]; then
       echo "Invalid IP"
       exit 1
   fi
   
   # After
   if ! parrot_validate_ipv4 "$ip"; then
       parrot_handle_error "$PARROT_ERR_INVALID_TARGET" "Invalid IP: $ip"
       exit "$PARROT_ERR_INVALID_TARGET"
   fi
   ```

3. Use structured error responses:
   ```bash
   # Generate and log error response
   error_json=$(parrot_format_error_response \
       "$PARROT_ERR_INVALID_INPUT" \
       "Invalid parameter" \
       "param_name" \
       "$provided_value" \
       "expected_format")
   
   echo "$error_json" >> "${PARROT_LOG_DIR}/error_responses.log"
   ```

## Related Documentation

- [USAGE.md](USAGE.md) - General usage guide
- [TESTING.md](../TESTING.md) - Testing guide
- [README.md](../README.md) - Project overview

## Support

For issues or questions:
1. Check the error code in this document
2. Review logs in `${PARROT_LOG_DIR}/`
3. Search error_responses.log for similar issues
4. Open an issue on GitHub with request ID for tracking
