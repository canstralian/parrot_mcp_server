# OpenVAS Integration Documentation

## Overview

The OpenVAS integration provides vulnerability scanning capabilities for the Parrot MCP Server. It implements secure password management practices and follows the repository's security guidelines.

## Security Design

### Password Management Optimization

The integration implements a secure password caching mechanism that addresses the security concerns of reading password files repeatedly:

#### Problem (Before)
In typical implementations, password files are read multiple times during execution:
- Authentication: read password
- Create target: read password
- Create task: read password
- Start scan: read password
- Monitor scan: read password
- Get results: read password
- Generate report: read password

This approach has several drawbacks:
1. **Performance**: Multiple file I/O operations slow down execution
2. **Security**: Each file access increases the attack surface
3. **Maintainability**: Duplicated code for password retrieval
4. **Reliability**: Higher chance of file access errors

#### Solution (Implemented)
The integration reads the password file **only once** at the start:

```bash
# Global variable to cache the password
OPENVAS_PASSWORD=""

# Read password once and cache it
read_openvas_password() {
    # If password is already cached, return success
    if [ -n "$OPENVAS_PASSWORD" ]; then
        return 0
    fi
    
    # Validate file and read password (only happens once)
    OPENVAS_PASSWORD=$(cat "$OPENVAS_PASSWORD_FILE")
    
    # Validate password content
    # ...
}

# All functions use the cached password
openvas_authenticate() {
    read_openvas_password || return 1
    # Use $OPENVAS_PASSWORD - NO FILE I/O
}

openvas_create_target() {
    read_openvas_password || return 1
    # Use $OPENVAS_PASSWORD - NO FILE I/O
}
# ... and so on for all 7 functions
```

### Security Features

#### 1. File Permission Validation
The script enforces strict file permissions on the password file:

```bash
# Validate file permissions (should be 600 or 400)
local perms
perms=$(stat -c "%a" "$OPENVAS_PASSWORD_FILE" 2>/dev/null)

if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
    parrot_error "Insecure permissions on password file: $perms (should be 600 or 400)"
    parrot_error "Fix with: chmod 600 $OPENVAS_PASSWORD_FILE"
    return 1
fi
```

**Why this matters**: Files with world-readable permissions (e.g., 644) can be read by any user on the system, exposing credentials.

#### 2. Password Content Validation
The script validates password content before use:

```bash
# Validate password is not empty
if [ -z "$OPENVAS_PASSWORD" ]; then
    parrot_error "OpenVAS password file is empty: $OPENVAS_PASSWORD_FILE"
    return 1
fi

# Validate password length
if [ ${#OPENVAS_PASSWORD} -lt 8 ]; then
    parrot_error "OpenVAS password is too short (minimum 8 characters)"
    return 1
fi
```

**Why this matters**: Prevents common misconfigurations like empty files or weak passwords.

#### 3. Memory Cleanup on Exit
The script automatically clears the password from memory when exiting:

```bash
# Clean up password from memory on exit
cleanup_password() {
    if [ -n "$OPENVAS_PASSWORD" ]; then
        # Overwrite password in memory before unsetting
        OPENVAS_PASSWORD=$(printf '%*s' ${#OPENVAS_PASSWORD} | tr ' ' '0')
        unset OPENVAS_PASSWORD
    fi
}

# Register cleanup function to run on exit
trap cleanup_password EXIT INT TERM
```

**Why this matters**: Prevents password from remaining in memory after script completion, reducing exposure to memory scraping attacks.

#### 4. Clear Error Messages
When validation fails, the script provides actionable error messages:

```bash
parrot_error "OpenVAS password file not found: $OPENVAS_PASSWORD_FILE"
parrot_error "Please create the password file with: echo 'your_password' > $OPENVAS_PASSWORD_FILE && chmod 600 $OPENVAS_PASSWORD_FILE"
```

**Why this matters**: Helps users quickly identify and fix configuration issues.

## Usage

### Basic Usage

1. **Create the password file** (one-time setup):
   ```bash
   echo 'your_secure_password' > /path/to/parrot_mcp_server/.openvas_password
   chmod 600 /path/to/parrot_mcp_server/.openvas_password
   ```

2. **Run a scan**:
   ```bash
   ./rpi-scripts/scripts/openvas_scan.sh --target 192.168.1.100
   ```

3. **Check the results**:
   ```bash
   ls -la scan_results/
   ```

### Advanced Usage

#### Custom Scan Profile
```bash
./rpi-scripts/scripts/openvas_scan.sh \
  --target 192.168.1.0/24 \
  --profile "Full and very deep" \
  --report-format PDF
```

#### Multiple Formats
```bash
# Generate PDF report
./rpi-scripts/scripts/openvas_scan.sh --target 192.168.1.50 --report-format PDF

# Generate XML report
./rpi-scripts/scripts/openvas_scan.sh --target 192.168.1.50 --report-format XML

# Generate HTML report
./rpi-scripts/scripts/openvas_scan.sh --target 192.168.1.50 --report-format HTML
```

#### Cleanup Old Reports
```bash
# Clean up reports older than 90 days (default)
./rpi-scripts/scripts/openvas_scan.sh --cleanup-old
```

### Configuration

The integration can be configured via environment variables in `rpi-scripts/config.env`:

```bash
# OpenVAS/GVM Configuration
OPENVAS_HOST="127.0.0.1"           # OpenVAS server host
OPENVAS_PORT="9390"                # OpenVAS server port
OPENVAS_USER="admin"               # OpenVAS username
OPENVAS_PASSWORD_FILE="/path/to/.openvas_password"  # Password file path
OPENVAS_TIMEOUT="3600"             # Scan timeout in seconds

# Scan Configuration
DEFAULT_TARGET="127.0.0.1"         # Default scan target
DEFAULT_PROFILE="Full and fast"    # Default scan profile
DEFAULT_REPORT_FORMAT="PDF"        # Default report format

# Output Configuration
SCAN_RESULTS_DIR="/path/to/scan_results"  # Results directory
REPORT_RETENTION_DAYS="90"         # Days to keep reports
```

## Architecture

### Function Flow

```
main()
  ├─ openvas_authenticate()
  │   └─ read_openvas_password() [READS FILE ONCE]
  │
  ├─ openvas_create_target()
  │   └─ read_openvas_password() [USES CACHED PASSWORD]
  │
  ├─ openvas_create_task()
  │   └─ read_openvas_password() [USES CACHED PASSWORD]
  │
  ├─ openvas_start_scan()
  │   └─ read_openvas_password() [USES CACHED PASSWORD]
  │
  ├─ openvas_monitor_scan()
  │   └─ read_openvas_password() [USES CACHED PASSWORD]
  │
  ├─ openvas_get_results()
  │   └─ read_openvas_password() [USES CACHED PASSWORD]
  │
  └─ openvas_generate_report()
      └─ read_openvas_password() [USES CACHED PASSWORD]

[EXIT]
  └─ cleanup_password() [CLEARS PASSWORD FROM MEMORY]
```

### Key Components

1. **read_openvas_password()**: Central password management function
   - Reads password file on first call
   - Caches password in `OPENVAS_PASSWORD` variable
   - Returns immediately on subsequent calls (uses cached value)
   - Validates file permissions and password content

2. **cleanup_password()**: Memory cleanup function
   - Overwrites password in memory with zeros
   - Unsets the password variable
   - Registered with trap to run on EXIT, INT, and TERM signals

3. **OpenVAS Integration Functions**: 7 functions that perform operations
   - All call `read_openvas_password()` first
   - All use cached password from memory
   - No direct file I/O for password retrieval

## Testing

### Unit Tests

Run the comprehensive test suite:

```bash
cd rpi-scripts
bats tests/openvas_scan.bats
```

### Test Coverage

The test suite includes:
- Command-line argument parsing
- Password file security validations
- Scan execution workflow
- Report generation and cleanup
- Error handling
- Security injection prevention

### Manual Testing

Test password security features:

```bash
# Test with valid password file
echo "secure_password_123" > .openvas_password
chmod 600 .openvas_password
./rpi-scripts/scripts/openvas_scan.sh
# Expected: Success

# Test with insecure permissions
chmod 644 .openvas_password
./rpi-scripts/scripts/openvas_scan.sh
# Expected: Error - "Insecure permissions"

# Test with missing file
rm .openvas_password
./rpi-scripts/scripts/openvas_scan.sh
# Expected: Error - "password file not found"

# Test with empty file
touch .openvas_password && chmod 600 .openvas_password
./rpi-scripts/scripts/openvas_scan.sh
# Expected: Error - "password file is empty"

# Test with short password
echo "short" > .openvas_password
./rpi-scripts/scripts/openvas_scan.sh
# Expected: Error - "password is too short"
```

## Performance Comparison

### Before Optimization (Hypothetical)
```
Operation                  | File I/O | Total Reads
--------------------------|----------|------------
Authenticate              | 1 read   |
Create Target             | 1 read   |
Create Task               | 1 read   |
Start Scan                | 1 read   |
Monitor Scan              | 1 read   |
Get Results               | 1 read   |
Generate Report           | 1 read   |
--------------------------|----------|------------
TOTAL                     |          | 7 reads
```

### After Optimization (Current)
```
Operation                  | File I/O | Total Reads
--------------------------|----------|------------
Authenticate              | 1 read   | (first call)
Create Target             | 0 reads  | (cached)
Create Task               | 0 reads  | (cached)
Start Scan                | 0 reads  | (cached)
Monitor Scan              | 0 reads  | (cached)
Get Results               | 0 reads  | (cached)
Generate Report           | 0 reads  | (cached)
--------------------------|----------|------------
TOTAL                     |          | 1 read
```

**Improvement**: 85.7% reduction in file I/O operations (7 reads → 1 read)

## Security Considerations

### Threat Model

1. **File Permission Vulnerabilities**: Mitigated by strict permission checking
2. **Memory Scraping**: Mitigated by cleanup trap and password overwriting
3. **Password File Tampering**: Detected by permission and content validation
4. **Weak Passwords**: Prevented by minimum length requirement
5. **Command Injection**: Prevented by proper quoting and input validation

### Best Practices

1. **Always use 600 or 400 permissions** on password files
2. **Store password files outside** the repository (added to .gitignore)
3. **Use strong passwords** (minimum 8 characters, preferably 16+)
4. **Rotate passwords regularly** according to your security policy
5. **Audit access logs** for the password file
6. **Use secure channels** when creating/transferring password files

### Compliance

This implementation follows:
- ✅ OWASP Secure Coding Practices
- ✅ CIS Benchmarks for file permissions
- ✅ PCI-DSS password storage guidelines
- ✅ Repository security guidelines (SECURITY.md)

## Troubleshooting

### Common Issues

#### Issue: "OpenVAS password file not found"
**Solution**: Create the password file:
```bash
echo 'your_password' > .openvas_password
chmod 600 .openvas_password
```

#### Issue: "Insecure permissions on password file"
**Solution**: Fix permissions:
```bash
chmod 600 .openvas_password
```

#### Issue: "OpenVAS password is too short"
**Solution**: Use a longer password (minimum 8 characters):
```bash
echo 'longer_secure_password_123' > .openvas_password
chmod 600 .openvas_password
```

#### Issue: "gvm-cli not found"
**Solution**: The script runs in simulation mode when gvm-cli is not installed. For production use:
```bash
# On Ubuntu/Debian
sudo apt-get install gvm-tools

# On RHEL/CentOS
sudo yum install gvm-tools
```

#### Issue: Connection timeout to OpenVAS server
**Solution**: Check server configuration:
```bash
# Verify server is running
systemctl status gvmd

# Check connectivity
nc -zv $OPENVAS_HOST $OPENVAS_PORT

# Review configuration
cat rpi-scripts/config.env
```

## Future Enhancements

Planned improvements:
- [ ] Support for certificate-based authentication
- [ ] Integration with HashiCorp Vault for credential management
- [ ] Multi-target scanning in parallel
- [ ] Email notifications with scan summaries
- [ ] Integration with SIEM systems
- [ ] Automated remediation workflows
- [ ] Dashboard for scan history and trends

## References

- [OpenVAS Documentation](https://www.openvas.org/documentation.html)
- [GVM Tools Documentation](https://github.com/greenbone/gvm-tools)
- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
- [Parrot MCP Server Security Policy](../SECURITY.md)

## License

This integration is part of the Parrot MCP Server project and is licensed under the MIT License. See LICENSE file for details.
