# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the Parrot MCP Server.

## Table of Contents

- [Configuration Issues](#configuration-issues)
- [Permission Errors](#permission-errors)
- [Script Execution Errors](#script-execution-errors)
- [Logging Issues](#logging-issues)
- [Email Notification Problems](#email-notification-problems)
- [MCP Server Issues](#mcp-server-issues)
- [Testing Failures](#testing-failures)
- [Performance Issues](#performance-issues)

---

## Configuration Issues

### Issue: Configuration not loading

**Symptoms**:
- Scripts use default values instead of config.env values
- Changes to config.env have no effect

**Diagnosis**:
```bash
# Check if config.env exists
ls -la rpi-scripts/config.env

# Check for syntax errors
bash -n rpi-scripts/config.env
echo $?  # Should output 0

# Enable debug mode
PARROT_DEBUG=true ./rpi-scripts/scripts/health_check.sh
```

**Solutions**:

1. **Verify file location**:
   ```bash
   # config.env must be in rpi-scripts/ directory
   cd /opt/parrot
   ls rpi-scripts/config.env  # Should exist
   ```

2. **Check syntax errors**:
   ```bash
   # Common errors:
   # - Missing quotes: PARROT_EMAIL=admin@example.com  (wrong)
   # - Correct: PARROT_EMAIL="admin@example.com"

   # Validate syntax
   bash -n rpi-scripts/config.env
   ```

3. **Ensure proper sourcing**:
   ```bash
   # Scripts should source common_config.sh
   grep -n "source.*common_config.sh" rpi-scripts/scripts/*.sh
   ```

4. **Check file permissions**:
   ```bash
   chmod 644 rpi-scripts/config.env
   ```

---

## Permission Errors

### Issue: "Permission denied" when running scripts

**Symptoms**:
- `bash: ./script.sh: Permission denied`
- Scripts won't execute

**Diagnosis**:
```bash
# Check execute permissions
ls -la rpi-scripts/scripts/health_check.sh

# Expected: -rwxr-xr-x (executable)
# If showing: -rw-r--r-- (not executable)
```

**Solutions**:

```bash
# Option 1: Make single script executable
chmod +x rpi-scripts/scripts/health_check.sh

# Option 2: Make all scripts executable
chmod +x rpi-scripts/*.sh rpi-scripts/scripts/*.sh

# Option 3: Use Makefile
cd rpi-scripts && make
```

### Issue: "Permission denied" for log directory

**Symptoms**:
- `mkdir: cannot create directory 'logs': Permission denied`
- No log files are created

**Diagnosis**:
```bash
# Check log directory permissions
ls -ld logs/

# Check parent directory permissions
ls -ld .
```

**Solutions**:

```bash
# Create log directory with correct permissions
mkdir -p logs
chmod 755 logs

# Or let common_config.sh create it automatically
PARROT_LOG_DIR="./logs" ./rpi-scripts/scripts/health_check.sh
```

### Issue: Cannot write to IPC directory

**Symptoms**:
- `mkfifo: cannot create fifo '/run/parrot-mcp/mcp.fifo': Permission denied`

**Solutions**:

```bash
# Create IPC directory as root
sudo mkdir -p /run/parrot-mcp
sudo chown $USER:$USER /run/parrot-mcp
sudo chmod 700 /run/parrot-mcp

# Or use user directory
# In config.env:
PARROT_IPC_DIR="$HOME/.parrot-mcp"
```

---

## Script Execution Errors

### Issue: `common_config.sh: No such file or directory`

**Symptoms**:
- Script fails with "source: common_config.sh: file not found"

**Diagnosis**:
```bash
# Check current directory
pwd

# Check if common_config.sh exists
ls rpi-scripts/common_config.sh
```

**Solutions**:

1. **Run scripts from project root**:
   ```bash
   cd /opt/parrot
   ./rpi-scripts/scripts/health_check.sh
   ```

2. **Or run from rpi-scripts directory**:
   ```bash
   cd /opt/parrot/rpi-scripts
   ./scripts/health_check.sh
   ```

3. **Check script's SCRIPT_DIR calculation**:
   ```bash
   # Should be in script:
   SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
   source "${SCRIPT_DIR}/common_config.sh"
   ```

### Issue: `set -u` errors - "unbound variable"

**Symptoms**:
- `line 42: VARIABLE: unbound variable`

**Diagnosis**:
```bash
# Enable trace mode to find unset variables
bash -x ./rpi-scripts/scripts/health_check.sh
```

**Solutions**:

```bash
# Option 1: Set variable in config.env
echo 'PARROT_ALERT_EMAIL=""' >> rpi-scripts/config.env

# Option 2: Use default value in script
ALERT_EMAIL="${PARROT_ALERT_EMAIL:-}"

# Option 3: Temporarily disable set -u
set +u
./script.sh
set -u
```

### Issue: "command not found" for tools

**Symptoms**:
- `jq: command not found`
- `bc: command not found`
- `mail: command not found`

**Solutions**:

```bash
# Install required tools
sudo apt-get update
sudo apt-get install jq bc mailutils

# Or check if tool is available first
if command -v jq >/dev/null 2>&1; then
    # Use jq
else
    echo "jq not available, skipping JSON validation"
fi
```

---

## Logging Issues

### Issue: Log files not created

**Symptoms**:
- No log files in `logs/` directory
- Commands execute but no logs appear

**Diagnosis**:
```bash
# Check log directory
ls -la logs/

# Check PARROT_LOG_DIR
echo "$PARROT_LOG_DIR"

# Run with debug mode
PARROT_DEBUG=true ./rpi-scripts/scripts/health_check.sh
```

**Solutions**:

```bash
# Ensure log directory exists
mkdir -p logs
chmod 755 logs

# Verify PARROT_LOG_DIR is set correctly
# In config.env:
PARROT_LOG_DIR="./logs"

# Check disk space
df -h .
```

### Issue: Logs not rotating

**Symptoms**:
- Log files grow indefinitely
- Disk space running low

**Solutions**:

```bash
# Manual log rotation
./rpi-scripts/scripts/log_rotate.sh

# Set up automatic rotation with cron
./rpi-scripts/scripts/setup_cron.sh

# Configure log rotation in config.env
PARROT_LOG_MAX_SIZE="10M"
PARROT_LOG_MAX_AGE="30"
PARROT_LOG_ROTATION_COUNT="5"
```

### Issue: Cannot read log files

**Symptoms**:
- `cat: logs/parrot.log: Permission denied`

**Solutions**:

```bash
# Fix log file permissions
chmod 644 logs/*.log

# Or if PARROT_STRICT_PERMS is enabled:
chmod 600 logs/*.log
sudo chown $USER logs/*.log
```

---

## Email Notification Problems

### Issue: Email notifications not sending

**Symptoms**:
- Health checks complete but no emails received
- No error messages about email

**Diagnosis**:
```bash
# Check if email is configured
echo "${PARROT_ALERT_EMAIL:-}"

# Test mail command
echo "Test" | mail -s "Test" "${PARROT_ALERT_EMAIL:-}"

# Check mail logs
tail -f /var/log/mail.log
```

**Solutions**:

1. **Configure email address**:
   ```bash
   # In config.env:
   PARROT_ALERT_EMAIL="admin@example.com"
   ```

2. **Install mail utilities**:
   ```bash
   sudo apt-get install mailutils
   ```

3. **Configure SMTP**:
   ```bash
   # For Gmail, configure /etc/ssmtp/ssmtp.conf
   sudo nano /etc/ssmtp/ssmtp.conf
   ```

4. **Test with parrot_send_notification**:
   ```bash
   # In a script:
   source rpi-scripts/common_config.sh
   parrot_send_notification "Test" "This is a test message"
   ```

### Issue: Invalid email address error

**Symptoms**:
- `Invalid email address: user@example`

**Solutions**:

```bash
# Email must have valid format:
# - user@domain.tld
# - user+tag@subdomain.domain.tld

# Valid:
PARROT_ALERT_EMAIL="admin@example.com"

# Invalid:
PARROT_ALERT_EMAIL="admin@localhost"  # No TLD
PARROT_ALERT_EMAIL="admin"  # No domain
```

---

## MCP Server Issues

### Issue: MCP server not starting

**Symptoms**:
- `./rpi-scripts/start_mcp_server.sh` exits immediately
- No MCP server process running

**Diagnosis**:
```bash
# Check if server is running
pgrep -f start_mcp_server.sh

# Check PID file
cat logs/mcp_server.pid

# Check server logs
tail -f logs/parrot.log
```

**Solutions**:

```bash
# Start server in foreground for debugging
./rpi-scripts/start_mcp_server.sh

# Check for port conflicts
lsof -i :3000

# Ensure IPC files are accessible
ls -la /tmp/mcp_in.json

# Start server with clean state
./rpi-scripts/stop_mcp_server.sh
rm -f /tmp/mcp_*.json
./rpi-scripts/start_mcp_server.sh
```

### Issue: Server doesn't process messages

**Symptoms**:
- Messages sent to `/tmp/mcp_in.json` are not processed
- Server appears running but unresponsive

**Diagnosis**:
```bash
# Send test message
echo '{"method":"ping"}' > /tmp/mcp_in.json

# Wait and check logs
sleep 2
tail logs/parrot.log

# Check if file is being read
watch -n 1 'ls -la /tmp/mcp_in.json'
```

**Solutions**:

```bash
# Restart server
./rpi-scripts/stop_mcp_server.sh
./rpi-scripts/start_mcp_server.sh

# Validate JSON format
echo '{"method":"ping","params":{}}' | jq .

# Check file permissions - use shared group instead of world-writable
chmod 660 /tmp/mcp_in.json
```

### Issue: Malformed JSON messages

**Symptoms**:
- Messages moved to `/tmp/mcp_bad.json`

**Solutions**:

```bash
# Check malformed messages
cat /tmp/mcp_bad.json | jq .

# Common JSON errors:
# - Missing quotes: {method: ping}  # Wrong
# - Correct: {"method": "ping"}

# Validate before sending
echo '{"method":"ping"}' | jq . && echo "Valid JSON"
```

---

## Testing Failures

### Issue: BATS tests failing

**Symptoms**:
- `bats rpi-scripts/tests/` reports failures

**Diagnosis**:
```bash
# Run tests with verbose output
bats -t rpi-scripts/tests/config_validation.bats

# Run single test
bats -f "parrot_validate_email" rpi-scripts/tests/config_validation.bats
```

**Solutions**:

1. **Install BATS**:
   ```bash
   sudo apt-get install bats
   ```

2. **Check test dependencies**:
   ```bash
   # Tests require:
   command -v jq || sudo apt-get install jq
   command -v bc || sudo apt-get install bc
   ```

3. **Fix permission issues**:
   ```bash
   chmod +x rpi-scripts/tests/*.bats
   chmod +x rpi-scripts/*.sh
   ```

4. **Check test output**:
   ```bash
   # Tests create temp directories
   # Ensure /tmp is writable
   touch /tmp/test && rm /tmp/test
   ```

### Issue: ShellCheck warnings

**Symptoms**:
- CI/CD pipeline fails on linting
- ShellCheck reports issues

**Solutions**:

```bash
# Run ShellCheck locally
shellcheck rpi-scripts/**/*.sh

# Fix common issues:
# - Quote variables: "$variable" not $variable
# - Use arrays for commands
# - Avoid 'which', use 'command -v'

# Disable specific warnings with comments:
# shellcheck disable=SC2086
echo $unquoted_var
```

---

## Performance Issues

### Issue: High CPU usage

**Symptoms**:
- Server consumes 100% CPU
- System becomes unresponsive

**Diagnosis**:
```bash
# Check CPU usage
top -p $(pgrep -f start_mcp_server.sh)

# Profile script
bash -x ./rpi-scripts/start_mcp_server.sh &
sleep 10
strace -p $(pgrep -f start_mcp_server.sh)
```

**Solutions**:

```bash
# Increase sleep interval in server loop
# In start_mcp_server.sh:
sleep 1  # Instead of sleep 0.1

# Use inotifywait for event-driven processing
inotifywait -m /tmp/mcp_in.json | while read event; do
    process_message
done
```

### Issue: Slow health checks

**Symptoms**:
- Health checks take minutes to complete
- Scripts hang

**Diagnosis**:
```bash
# Time the script
time ./rpi-scripts/scripts/health_check.sh

# Enable trace mode
PARROT_TRACE=true ./rpi-scripts/scripts/health_check.sh
```

**Solutions**:

```bash
# Disable slow checks
# In config.env:
PARROT_DISK_THRESHOLD="99"  # Skip disk checks

# Run checks in parallel
check_disk &
check_load &
wait

# Reduce timeout values
PARROT_COMMAND_TIMEOUT="30"  # Reduce from 300s
```

---

## Common Error Messages

### `line 42: PARROT_BASE_DIR: unbound variable`

**Cause**: Configuration not loaded
**Fix**: Source common_config.sh at top of script

### `Invalid disk threshold: 101 (must be 0-100)`

**Cause**: Invalid command-line argument
**Fix**: Use valid percentage: `--disk-threshold 85`

### `Failed to check disk usage`

**Cause**: `df` command failed
**Fix**: Check disk is mounted: `df -h /`

### `Invalid JSON syntax in: /tmp/mcp_in.json`

**Cause**: Malformed JSON message
**Fix**: Validate JSON: `echo '{"method":"ping"}' | jq .`

### `Cannot create directory 'logs': Permission denied`

**Cause**: No write permission in current directory
**Fix**: `chmod 755 . && mkdir -p logs`

---

## Debugging Techniques

### Enable Debug Mode

```bash
# Method 1: Environment variable
PARROT_DEBUG=true ./script.sh

# Method 2: config.env
echo 'PARROT_DEBUG="true"' >> rpi-scripts/config.env

# Method 3: Trace mode
PARROT_TRACE=true ./script.sh
```

### Check Log Files

```bash
# Tail all logs
tail -f logs/*.log

# Search for errors
grep ERROR logs/parrot.log

# Search for specific message ID
grep "msgid:1731322245123456789" logs/*.log
```

### Dry Run Mode

```bash
# Test without making changes
PARROT_DRY_RUN=true ./rpi-scripts/scripts/daily_workflow.sh
```

### Verbose Testing

```bash
# Run tests with verbose output
bats -t rpi-scripts/tests/*.bats

# Run single test with debug
PARROT_DEBUG=true bats -f "validate_email" rpi-scripts/tests/config_validation.bats
```

---

## Getting Help

If you've tried the solutions above and still have issues:

1. **Check the logs**:
   ```bash
   tail -n 100 logs/parrot.log
   tail -n 100 logs/cli_error.log
   ```

2. **Enable debug mode**:
   ```bash
   PARROT_DEBUG=true ./your-script.sh 2>&1 | tee debug.log
   ```

3. **Create a minimal reproduction**:
   ```bash
   # Create simple test case
   cat > test.sh << 'EOF'
   #!/usr/bin/env bash
   set -euo pipefail
   source rpi-scripts/common_config.sh
   parrot_info "Testing"
   EOF
   bash test.sh
   ```

4. **Report the issue**:
   - Include: OS version, Bash version, error messages
   - Attach: Relevant log files, debug output
   - Describe: Steps to reproduce
   - See: [SECURITY.md](../SECURITY.md) for reporting security issues

---

## Related Documentation

- [Configuration Guide](CONFIGURATION.md) - Configure the system
- [Security Policy](../SECURITY.md) - Security best practices
- [IPC Security](IPC_SECURITY.md) - Secure IPC implementation
- [Logging Standards](LOGGING.md) - Log format specifications

---

**Last Updated**: 2025-11-11
