# Security Improvements

This document outlines the security improvements made to address the TODO items related to secure inter-process communication and input validation.

## Overview

The following security enhancements have been implemented:

1. **Replaced `/tmp` usage with secure named pipes**
2. **Added comprehensive input validation functions**
3. **Implemented secure temporary file handling**
4. **Created example client demonstrating secure IPC**

## 1. Secure Named Pipes for IPC

### Problem
Previously, the MCP server used `/tmp/mcp_in.json` and `/tmp/mcp_bad.json` for inter-process communication, which created several security vulnerabilities:
- Race conditions
- World-readable files
- Predictable paths
- Symlink attacks

### Solution
Replaced file-based IPC with **secure named pipes** (FIFOs) with restrictive permissions:

#### Implementation Details

**Location**: Named pipes are created in a secure directory:
- Primary: `$XDG_RUNTIME_DIR/parrot_mcp` (if available)
- Fallback: `<project_root>/runtime/`

**Permissions**: All pipes are created with `umask 0077`, resulting in mode `0600` (owner read/write only).

**Cleanup**: Pipes are automatically cleaned up on server shutdown via trap handlers.

#### Modified Files

- `rpi-scripts/common_config.sh`: Added IPC configuration and utility functions
  - `parrot_init_ipc_dir()`: Creates IPC directory with secure permissions
  - `parrot_create_pipe()`: Creates named pipes with umask 0077
  - `parrot_cleanup_pipes()`: Removes named pipes on cleanup

- `rpi-scripts/start_mcp_server.sh`: Rewritten to use named pipes
  - Creates input and output pipes on startup
  - Reads from input pipe in a loop
  - Writes responses to output pipe
  - Cleans up pipes on exit/interrupt

- `rpi-scripts/stop_mcp_server.sh`: Enhanced with pipe cleanup
  - Stops the server process
  - Removes named pipes
  - Logs all actions

- `rpi-scripts/test_mcp_local.sh`: Updated to use named pipes
  - Waits for pipes to be created
  - Sends messages via input pipe
  - Reads responses from output pipe

#### Usage Example

```bash
# Start the server
./rpi-scripts/start_mcp_server.sh

# Send a message using the client example
./rpi-scripts/mcp_client_example.sh '{"type":"mcp_message","content":"ping"}'

# Stop the server (automatically cleans up pipes)
./rpi-scripts/stop_mcp_server.sh
```

## 2. Input Validation

### Problem
Scripts lacked comprehensive input validation, leading to potential security vulnerabilities:
- Command injection attacks
- Path traversal vulnerabilities
- Denial of service through malformed input

### Solution
Added validation functions for common input types.

#### Bash Validation Functions

Added to `rpi-scripts/common_config.sh`:

**IPv4 Address Validation**:
```bash
parrot_validate_ipv4() {
    local ip="$1"
    local octet="([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])"
    if [[ ! "$ip" =~ ^${octet}\.${octet}\.${octet}\.${octet}$ ]]; then
        return 1
    fi
    return 0
}
```

**Port Number Validation** (1-65535):
```bash
parrot_validate_port() {
    local port="$1"
    if ! parrot_validate_number "$port"; then
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}
```

**Existing Validation Functions**:
- `parrot_validate_email()`: Email address validation
- `parrot_validate_number()`: Numeric value validation
- `parrot_validate_percentage()`: Percentage (0-100) validation
- `parrot_validate_path()`: Safe path validation (prevents traversal)
- `parrot_validate_script_name()`: Script name validation
- `parrot_sanitize_input()`: Input sanitization (removes dangerous characters)

#### Python Validation Module

Created `rpi-scripts/validation.py` with reusable validation functions:

**Features**:
- IPv4 address validation with regex
- Port number validation (1-65535)
- Email address validation
- Input sanitization
- Command-line interface for standalone usage

**Usage**:
```bash
# Validate IP address
python3 rpi-scripts/validation.py ipv4 192.168.1.1

# Validate port number
python3 rpi-scripts/validation.py port 8080

# Validate email
python3 rpi-scripts/validation.py email user@example.com
```

**Python Import Usage**:
```python
from validation import validate_ipv4, validate_port, validate_email

if validate_ipv4("192.168.1.1"):
    print("Valid IP address")

if validate_port(8080):
    print("Valid port")

if validate_email("user@example.com"):
    print("Valid email")
```

#### Testing

A test script `rpi-scripts/test_validation.sh` demonstrates all validation functions:

```bash
./rpi-scripts/test_validation.sh
```

Output:
```
=== Testing IP Address Validation ===
✓ Valid IPv4: 192.168.1.1
✓ Valid IPv4: 10.0.0.1
✗ Invalid IPv4: 256.1.1.1
✗ Invalid IPv4: invalid.ip
✓ Valid IPv4: 127.0.0.1

=== Testing Port Validation ===
✓ Valid port: 80
✓ Valid port: 443
✓ Valid port: 8080
✗ Invalid port: 0
✗ Invalid port: 70000
✓ Valid port: 3000

=== Testing Email Validation ===
✓ Valid email: user@example.com
✓ Valid email: test@test.co.uk
✗ Invalid email: invalid.email
✗ Invalid email: @example.com
✗ Invalid email: user@
```

## 3. Secure Temporary File Handling

### Problem
`rpi-scripts/scripts/setup_cron.sh` used a predictable path `/tmp/rpi_maintenance_cron` for temporary files.

### Solution
Updated to use `mktemp` for secure temporary file creation:

```bash
# Old (insecure)
CRON_FILE="/tmp/rpi_maintenance_cron"

# New (secure)
CRON_FILE=$(mktemp -t rpi_maintenance_cron.XXXXXX)
trap 'rm -f "$CRON_FILE"' EXIT
```

**Benefits**:
- Unique filename prevents race conditions
- Unpredictable path prevents attacks
- Trap ensures cleanup even on error

## 4. Example Client Script

Created `rpi-scripts/mcp_client_example.sh` to demonstrate secure IPC usage:

**Features**:
- Sends messages via secure named pipes
- Validates message size
- Sanitizes input
- Handles timeouts
- Provides clear error messages

**Usage**:
```bash
# Send a ping message
./rpi-scripts/mcp_client_example.sh '{"type":"mcp_message","content":"ping"}'

# Send with custom timeout
./rpi-scripts/mcp_client_example.sh --timeout 10 '{"type":"mcp_message","content":"hello"}'

# Show help
./rpi-scripts/mcp_client_example.sh --help
```

## Security Checklist

The following security improvements have been implemented:

- [x] Replace `/tmp` usage with secure named pipes
- [x] Implement restrictive file permissions (umask 0077)
- [x] Add cleanup logic for named pipes
- [x] Add IPv4 address validation
- [x] Add port number validation
- [x] Create Python validation module
- [x] Fix insecure temporary file creation in setup_cron.sh
- [x] Add example client demonstrating secure IPC
- [x] Add comprehensive test suite
- [x] Document all security improvements

## Future Improvements

Additional security enhancements that could be implemented:

1. **Authentication**: Add API key or token-based authentication for MCP clients
2. **TLS Support**: Implement TLS encryption for network-based deployments
3. **Rate Limiting**: Add rate limiting to prevent DoS attacks
4. **Message Signing**: Implement message signing for integrity verification
5. **SELinux/AppArmor**: Create security profiles for additional isolation

## References

- [Bash Security Best Practices](https://mywiki.wooledge.org/BashGuide/Practices)
- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [Named Pipes (FIFOs) - Linux man page](https://man7.org/linux/man-pages/man7/fifo.7.html)

## Testing

All changes have been validated:

1. **Linting**: All scripts pass ShellCheck
2. **Unit Tests**: Validation functions tested
3. **Integration Tests**: MCP server communication tested
4. **Manual Testing**: Client-server interaction verified

Run tests:
```bash
# Lint all scripts
shellcheck rpi-scripts/*.sh

# Run validation tests
./rpi-scripts/test_validation.sh

# Run MCP server tests
./rpi-scripts/test_mcp_local.sh

# Test client communication
./rpi-scripts/start_mcp_server.sh &
./rpi-scripts/mcp_client_example.sh '{"type":"mcp_message","content":"ping"}'
./rpi-scripts/stop_mcp_server.sh
```

## Conclusion

These security improvements significantly enhance the security posture of the Parrot MCP Server by:

1. Eliminating insecure `/tmp` file usage
2. Implementing secure IPC with named pipes
3. Adding comprehensive input validation
4. Providing reusable validation utilities
5. Following security best practices

All changes maintain backward compatibility where possible and are thoroughly tested.
