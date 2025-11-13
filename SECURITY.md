# Security Policy

## Overview

The Parrot MCP Server is a lightweight Model Context Protocol (MCP) implementation designed for Raspberry Pi 5 and edge computing environments. As a pure Bash-based implementation, it emphasizes transparency and auditability, but has specific security considerations that users and contributors should be aware of.

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          | Notes |
| ------- | ------------------ | ----- |
| 0.x.x   | :white_check_mark: | Current development version |

**Note**: This project is currently in active development and should be considered **prototype/experimental**. It is NOT recommended for production use without thorough security hardening.

## Release Verification

All official releases of the Parrot MCP Server are cryptographically signed with GPG keys to ensure authenticity and integrity. This helps protect against supply chain attacks and ensures you're installing legitimate, unmodified software.

### Release Signing Keys

Public GPG keys used for signing releases are stored in the `gpg-keys/` directory and follow this naming convention:
- `<first_version>-<last_version>.gpg` - For rotated keys
- `<first_version>-current.gpg` - For currently active keys

**Current Key Fingerprints**: *(To be added upon first release)*

### Verifying Releases

Each release includes:
- **GPG signatures** (`.asc` files) - Cryptographic signatures for all release artifacts
- **SHA-256 checksums** (`.sha256` files) - File integrity verification

**Before installing any release**, verify both the GPG signature and checksum to ensure the release is authentic and has not been tampered with.

For detailed instructions on verifying releases, see our comprehensive [Release Verification Guide](docs/RELEASES.md).

**Quick Verification**:
```bash
# Download release, signature, and checksum
wget https://github.com/canstralian/parrot_mcp_server/releases/download/v1.0.0/parrot-mcp-server-v1.0.0.tar.gz{,.asc,.sha256}

# Import public key
gpg --import gpg-keys/v1.0.0-current.gpg

# Verify signature
gpg --verify parrot-mcp-server-v1.0.0.tar.gz.asc parrot-mcp-server-v1.0.0.tar.gz

# Verify checksum
sha256sum -c parrot-mcp-server-v1.0.0.tar.gz.sha256
```

**⚠️ Security Warning**: If either verification fails, **DO NOT use the release**. It may have been compromised. Report the issue immediately through our security advisory process.

## Known Security Issues

### Critical Vulnerabilities

#### 1. Insecure Inter-Process Communication (IPC)
**Severity**: CRITICAL
**Status**: Known Issue (TODO item)

The current implementation uses `/tmp/mcp_in.json` and `/tmp/mcp_bad.json` for IPC, which creates several security risks:

- **Race Conditions**: Multiple processes can access these files simultaneously
- **World-Readable Files**: Sensitive data may be exposed to all users on the system
- **Predictable Paths**: Attackers can easily locate and manipulate these files
- **Symlink Attacks**: Files in `/tmp` are vulnerable to symlink-based attacks

**Mitigation Recommendations**:
- Use named pipes (FIFOs) with restricted permissions
- Implement Unix domain sockets for secure IPC
- Consider moving to a language with built-in secure IPC (Python, Go)
- If continuing with file-based IPC, use `/run/parrot/` with proper permissions (700)

#### 2. Missing Input Validation
**Severity**: HIGH
**Status**: Known Issue (TODO item)

Scripts that accept user input or read from files currently lack comprehensive input validation and sanitization. This could lead to:

- Command injection attacks
- Path traversal vulnerabilities
- Denial of service through malformed input
- Unexpected behavior with edge cases

**Current Mitigations**:
- `cli.sh` validates script names using regex: `^[a-zA-Z_][a-zA-Z0-9_-]*$`
- Scripts use `set -euo pipefail` for basic error handling

**Required Improvements**:
- Add input validation to all scripts accepting user-supplied data
- Sanitize file paths and arguments
- Validate JSON message format against MCP specification
- Implement size limits on input data

#### 3. No Authentication or Authorization
**Severity**: HIGH
**Status**: Known Issue

The MCP server stub currently has no authentication or authorization mechanism. Any process on the system can:

- Send messages to the server
- Read server responses
- Potentially manipulate server state

**Recommendations**:
- Implement API key authentication for MCP clients
- Add role-based access control (RBAC)
- Use Unix file permissions as a first layer of defense
- Consider TLS for network-based deployments

### Medium Severity Issues

#### 4. Insecure Cron Setup
**File**: `rpi-scripts/scripts/setup_cron.sh`

Issues:
- Uses predictable temp file path: `/tmp/rpi_maintenance_cron`
- Doesn't validate crontab content before installation
- No permission checks on temp file

**Mitigation**: Use `mktemp` for temporary files and validate permissions.

#### 5. Sudo Usage Without Validation
Multiple scripts use `sudo` for system operations without validating:
- Who is invoking the script
- Whether sudo access is actually needed
- Privilege escalation risks

**Recommendation**: Minimize sudo usage, use capabilities where possible, add privilege validation.

#### 6. No Secret Management
Email addresses and potentially sensitive configuration are stored in:
- Plain text environment variables
- Hardcoded values in scripts

**Recommendation**: Integrate with secret management systems (HashiCorp Vault, AWS Secrets Manager, or at minimum encrypted files).

### Low Severity Issues

#### 7. Hardcoded Log Paths
Log files use relative paths (`./logs/parrot.log`) which can lead to:
- Logs written to unexpected locations
- Permission issues
- Log injection vulnerabilities

**Recommendation**: Use absolute paths, validate log directory permissions, implement log rotation with size limits.

## Security Best Practices for Deployment

### System Hardening

1. **Run as Non-Root User**
   ```bash
   # Create dedicated user
   sudo useradd -r -s /bin/bash -d /opt/parrot parrot-mcp
   sudo chown -R parrot-mcp:parrot-mcp /opt/parrot
   ```

2. **Restrict File Permissions**
   ```bash
   chmod 700 /opt/parrot/rpi-scripts
   chmod 600 /opt/parrot/rpi-scripts/*.sh
   chmod 700 /opt/parrot/logs
   ```

3. **Use Secure IPC Directory**
   ```bash
   # Instead of /tmp, use /run
   sudo mkdir -p /run/parrot-mcp
   sudo chown parrot-mcp:parrot-mcp /run/parrot-mcp
   sudo chmod 700 /run/parrot-mcp
   ```

4. **Enable AppArmor/SELinux**
   - Create security profiles limiting file system access
   - Restrict network access if not needed
   - Limit process capabilities

5. **Regular Updates**
   ```bash
   # Keep system and scripts updated
   sudo apt update && sudo apt upgrade
   cd /opt/parrot && git pull
   ```

### Network Security (Future Considerations)

When transitioning to a network-enabled server:

1. **Use TLS/SSL**: Encrypt all network communication
2. **Implement Rate Limiting**: Prevent DoS attacks
3. **Add Request Authentication**: API keys, JWT tokens, or mTLS
4. **Enable Firewall Rules**: Restrict access to MCP port
5. **Monitor Traffic**: Log and analyze connection patterns

### Audit and Monitoring

1. **Enable Comprehensive Logging**
   - All scripts currently log to `./logs/parrot.log`
   - Ensure log files are protected (chmod 600)
   - Consider centralized logging (syslog, journald)

2. **Regular Security Audits**
   ```bash
   # Run ShellCheck on all scripts
   find rpi-scripts -name "*.sh" -exec shellcheck {} \;

   # Check for common vulnerabilities (word boundaries prevent false positives)
   grep -rE '\beval\b|\bexec\b|\$\(|`' rpi-scripts/
   ```

3. **Monitor File Integrity**
   - Use tools like `aide` or `tripwire`
   - Track changes to scripts and configuration

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue in the Parrot MCP Server, please report it responsibly.

### How to Report

**Preferred Method - GitHub Security Advisories**:
- Navigate to: https://github.com/canstralian/parrot_mcp_server/security/advisories/new
- Provide detailed information about the vulnerability
- This creates a private communication channel with maintainers

**Alternative Method - GitHub Issues**:
- Create an issue with label `security` at: https://github.com/canstralian/parrot_mcp_server/issues
- For sensitive issues, email the repository owner directly (check GitHub profile)

### What to Include in Your Report

Please provide as much detail as possible:

1. **Description**: Clear explanation of the vulnerability
2. **Impact**: Potential consequences if exploited
3. **Affected Versions**: Which versions are vulnerable
4. **Reproduction Steps**: Detailed steps to reproduce the issue
5. **Proof of Concept**: Code or commands demonstrating the vulnerability (if applicable)
6. **Suggested Fix**: Your recommendations for remediation (optional)
7. **Environment**: OS version, Bash version, hardware platform

### Example Report Format

```
## Vulnerability: Command Injection in health_check.sh

**Severity**: High
**Affected Versions**: All versions prior to 0.2.0

**Description**:
The health_check.sh script uses user-supplied email addresses without
proper sanitization, allowing command injection via the ALERT_EMAIL
environment variable.

**Reproduction**:
1. Set: export ALERT_EMAIL='test@example.com; rm -rf /'
2. Run: ./rpi-scripts/scripts/health_check.sh
3. Observe command injection

**Impact**:
Arbitrary command execution with privileges of the script user.

**Suggested Fix**:
Validate email format using regex before use:
[[ "$ALERT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
```

### What to Expect

1. **Acknowledgment**: We will acknowledge receipt within 72 hours
2. **Assessment**: We'll assess severity and impact within 1 week
3. **Updates**: Regular updates every 1-2 weeks during investigation
4. **Fix Timeline**:
   - Critical: Within 7 days
   - High: Within 30 days
   - Medium: Within 90 days
   - Low: Next scheduled release
5. **Disclosure**: Coordinated disclosure after fix is available
   - We'll credit researchers (with permission)
   - CVE assignment for significant vulnerabilities
   - Public security advisory published

### Security Response Process

1. **Triage**: Maintainers assess and prioritize the report
2. **Investigation**: Reproduce and analyze the vulnerability
3. **Development**: Create and test a fix
4. **Testing**: Verify fix doesn't introduce new issues
5. **Release**: Deploy fix to supported versions
6. **Announcement**: Publish security advisory
7. **Retrospective**: Document lessons learned

## Security Development Practices

### For Contributors

When contributing to this project:

1. **Follow Secure Coding Guidelines**:
   - Always use `set -euo pipefail` in scripts
   - Validate all input parameters
   - Quote all variables: `"$variable"`, not `$variable`
   - Use arrays for command arguments, not strings
   - Avoid `eval` and `exec` unless absolutely necessary

2. **Run Security Checks**:
   ```bash
   # Before committing
   shellcheck your_script.sh

   # Check for common issues
   grep -E 'eval|exec|\$\(' your_script.sh
   ```

3. **Test Error Conditions**:
   - Test with malformed input
   - Test with missing files/permissions
   - Test with unusual characters in input
   - Test with extremely large input

4. **Document Security Implications**:
   - Note any sudo requirements
   - Document file permissions needed
   - Explain security trade-offs in design decisions

### Code Review Checklist

For reviewers, check:

- [ ] Input validation present for all external data
- [ ] No use of `eval` or unsafe `exec`
- [ ] All variables properly quoted
- [ ] Error handling with `set -euo pipefail`
- [ ] No hardcoded credentials or secrets
- [ ] Secure file permissions (no 777)
- [ ] No predictable temporary file names
- [ ] Proper logging without sensitive data leakage
- [ ] ShellCheck passes with no warnings
- [ ] BATS tests include security edge cases

## Additional Resources

- **Release Verification Guide**: [docs/RELEASES.md](docs/RELEASES.md) - How to verify release authenticity
- **Bash Security Best Practices**: https://mywiki.wooledge.org/BashGuide/Practices
- **ShellCheck**: https://www.shellcheck.net/
- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **CWE Top 25**: https://cwe.mitre.org/top25/
- **MCP Specification**: https://modelcontextprotocol.io/

## Security Changelog

### Version 0.1.x (Current)
- Initial security policy documentation
- Known vulnerabilities documented
- Basic input validation in cli.sh
- Comprehensive logging framework

### Planned for 0.2.x
- [ ] Replace /tmp IPC with secure alternative
- [ ] Add input validation to all scripts
- [ ] Implement authentication framework
- [ ] Add rate limiting
- [ ] Integrate secret management

---

**Last Updated**: 2025-11-11
**Policy Version**: 1.0

Thank you for helping keep the Parrot MCP Server secure!
