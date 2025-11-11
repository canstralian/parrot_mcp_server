# Configuration Guide

This document explains how to configure the Parrot MCP Server using the centralized configuration system.

## Overview

The Parrot MCP Server uses a centralized configuration system that provides:

- **Default values** for all settings
- **Environment-specific overrides** via `config.env`
- **Validation functions** for secure input handling
- **Utility functions** for common tasks
- **Structured logging** with message IDs

## Quick Start

### 1. Create Your Configuration File

```bash
cd rpi-scripts
cp config.env.example config.env
```

### 2. Edit Configuration

Edit `config.env` with your preferred settings:

```bash
nano config.env
```

Key settings to customize:

```bash
# Email notifications
PARROT_ALERT_EMAIL="admin@example.com"
PARROT_NOTIFY_EMAIL="admin@example.com"

# Monitoring thresholds
PARROT_DISK_THRESHOLD="80"
PARROT_LOAD_THRESHOLD="2.0"

# Enable debug mode for troubleshooting
PARROT_DEBUG="false"
```

### 3. Use in Scripts

All scripts automatically load the configuration by sourcing `common_config.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"

# Now you can use configuration variables
parrot_info "Starting script with log level: $PARROT_LOG_LEVEL"

# Use utility functions
if parrot_validate_email "$PARROT_ALERT_EMAIL"; then
    parrot_info "Alert email is valid: $PARROT_ALERT_EMAIL"
fi
```

## Configuration Categories

### Paths and Directories

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_BASE_DIR` | Auto-detected | Base directory for installation |
| `PARROT_SCRIPT_DIR` | `${PARROT_BASE_DIR}/rpi-scripts` | Script directory |
| `PARROT_LOG_DIR` | `./logs` | Log file directory |
| `PARROT_IPC_DIR` | `/tmp` | IPC directory (**insecure**) |
| `PARROT_PID_FILE` | `${PARROT_LOG_DIR}/mcp_server.pid` | Server PID file |

**Security Note**: The default `PARROT_IPC_DIR=/tmp` is **insecure** for production use. See [SECURITY.md](../SECURITY.md) for secure alternatives.

### Logging Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_SERVER_LOG` | `${PARROT_LOG_DIR}/parrot.log` | Main server log |
| `PARROT_CLI_LOG` | `${PARROT_LOG_DIR}/cli_error.log` | CLI error log |
| `PARROT_HEALTH_LOG` | `${PARROT_LOG_DIR}/health_check.log` | Health check log |
| `PARROT_WORKFLOW_LOG` | `${PARROT_LOG_DIR}/daily_workflow.log` | Workflow log |
| `PARROT_LOG_LEVEL` | `INFO` | Log level: DEBUG, INFO, WARN, ERROR |
| `PARROT_LOG_MAX_SIZE` | `10M` | Max log size before rotation |
| `PARROT_LOG_MAX_AGE` | `30` | Days to keep rotated logs |
| `PARROT_LOG_ROTATION_COUNT` | `5` | Number of rotated logs to keep |

### System Monitoring

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_DISK_THRESHOLD` | `80` | Disk usage warning threshold (%) |
| `PARROT_LOAD_THRESHOLD` | `2.0` | Load average warning threshold |
| `PARROT_MEM_THRESHOLD` | `90` | Memory usage warning threshold (%) |

### Notification Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_ALERT_EMAIL` | (empty) | Email for health check alerts |
| `PARROT_NOTIFY_EMAIL` | (empty) | Email for workflow notifications |
| `PARROT_EMAIL_PREFIX` | `[Parrot MCP]` | Email subject prefix |

**Note**: Email notifications are disabled if these variables are empty.

### Security Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_RUN_AS_USER` | (empty) | User to run server as |
| `PARROT_STRICT_PERMS` | `true` | Enforce strict file permissions |
| `PARROT_VALIDATION_LEVEL` | `STRICT` | Input validation level |
| `PARROT_MAX_INPUT_SIZE` | `1048576` | Max input size (1MB) |

### Development and Debugging

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_DEBUG` | `false` | Enable verbose debug output |
| `PARROT_DRY_RUN` | `false` | Don't make actual changes |
| `PARROT_TRACE` | `false` | Enable bash trace mode (set -x) |

## Utility Functions

The `common_config.sh` library provides utility functions for common tasks.

### Logging Functions

#### parrot_log LEVEL "message"
Structured logging with automatic message IDs.

```bash
parrot_log "INFO" "Server starting"
# Output: [2025-11-11 10:30:45] [INFO] [msgid:1731322245123456789] Server starting
```

#### Convenience functions

```bash
parrot_debug "Detailed diagnostic information"
parrot_info "Normal informational message"
parrot_warn "Warning message"
parrot_error "Error message"
```

### Validation Functions

#### parrot_validate_email "email@example.com"
Validates email address format.

```bash
if parrot_validate_email "$PARROT_ALERT_EMAIL"; then
    echo "Valid email"
else
    echo "Invalid email format"
fi
```

#### parrot_validate_number "123"
Validates numeric input.

```bash
if parrot_validate_number "$threshold"; then
    echo "Valid number"
fi
```

#### parrot_validate_percentage "85"
Validates percentage (0-100).

```bash
if parrot_validate_percentage "$PARROT_DISK_THRESHOLD"; then
    echo "Valid percentage"
fi
```

#### parrot_validate_path "/path/to/file"
Validates file paths (checks for path traversal, null bytes).

```bash
if parrot_validate_path "$user_input"; then
    echo "Safe path"
else
    echo "Potentially dangerous path"
fi
```

#### parrot_validate_script_name "my_script"
Validates script names (alphanumeric, underscore, hyphen).

```bash
if parrot_validate_script_name "$script_name"; then
    echo "Valid script name"
fi
```

### Sanitization Functions

#### parrot_sanitize_input "user input"
Removes dangerous characters from input.

```bash
safe_input=$(parrot_sanitize_input "$user_input")
```

### System Functions

#### parrot_is_root
Check if running as root.

```bash
if parrot_is_root; then
    echo "Running as root"
else
    echo "Running as normal user"
fi
```

#### parrot_command_exists "command"
Check if a command is available.

```bash
if parrot_command_exists "jq"; then
    echo "jq is installed"
fi
```

### Notification Functions

#### parrot_send_notification "subject" "message" [recipient]
Send email notification.

```bash
parrot_send_notification "System Alert" "Disk usage critical"
# Uses PARROT_ALERT_EMAIL by default

parrot_send_notification "Test" "Hello" "admin@example.com"
# Override recipient
```

### Retry Functions

#### parrot_retry [max_attempts] command [args...]
Retry a command with exponential backoff.

```bash
# Retry with default settings (3 attempts, 5s initial delay)
parrot_retry wget "https://example.com/file.tar.gz"

# Retry with custom max attempts
parrot_retry 5 curl -f "https://api.example.com/status"
```

### Security Functions

#### parrot_check_perms "file" "expected_perms"
Check file permissions.

```bash
if parrot_check_perms "/etc/parrot/config" "600"; then
    echo "Permissions are correct"
fi
```

#### parrot_mktemp [template]
Create secure temporary file.

```bash
tmpfile=$(parrot_mktemp "myapp.XXXXXX")
echo "data" > "$tmpfile"
# File is automatically created with 600 permissions
```

#### parrot_validate_json "file.json"
Validate JSON file syntax and size.

```bash
if parrot_validate_json "$PARROT_MCP_INPUT"; then
    # Process JSON file
    jq '.method' "$PARROT_MCP_INPUT"
fi
```

## Environment Profiles

You can create different configuration profiles for different environments.

### Development Configuration

`config.dev.env`:
```bash
PARROT_DEBUG="true"
PARROT_DRY_RUN="true"
PARROT_LOG_LEVEL="DEBUG"
PARROT_ALERT_EMAIL="dev@example.com"
```

### Production Configuration

`config.prod.env`:
```bash
PARROT_DEBUG="false"
PARROT_DRY_RUN="false"
PARROT_LOG_LEVEL="INFO"
PARROT_ALERT_EMAIL="ops@example.com"
PARROT_STRICT_PERMS="true"
PARROT_IPC_DIR="/run/parrot-mcp"
```

### Using Profiles

```bash
# Development
ln -sf config.dev.env config.env

# Production
ln -sf config.prod.env config.env
```

Or load specific profile in scripts:

```bash
# Load specific profile
if [ -f "${PARROT_SCRIPT_DIR}/config.${ENV}.env" ]; then
    source "${PARROT_SCRIPT_DIR}/config.${ENV}.env"
fi
```

## Migration Guide

### Converting Existing Scripts

**Before** (hardcoded values):
```bash
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="./logs/my_script.log"
ALERT_EMAIL="${ALERT_EMAIL:-}"

echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Starting script" >> "$LOG_FILE"

if [ -n "$ALERT_EMAIL" ]; then
    echo "Error occurred" | mail -s "Alert" "$ALERT_EMAIL"
fi
```

**After** (using common_config):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"

# Set script-specific log file
PARROT_CURRENT_LOG="$PARROT_LOG_DIR/my_script.log"

parrot_info "Starting script"

if [ -n "${PARROT_ALERT_EMAIL:-}" ]; then
    parrot_send_notification "Alert" "Error occurred"
fi
```

## Best Practices

### 1. Always Source common_config.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"
```

### 2. Use Validation Functions

```bash
# Bad
if [ -n "$user_email" ]; then
    mail -s "Test" "$user_email"
fi

# Good
if parrot_validate_email "$user_email"; then
    parrot_send_notification "Test" "Message"
fi
```

### 3. Use Structured Logging

```bash
# Bad
echo "$(date) ERROR: Something failed" >> log.txt

# Good
parrot_error "Something failed"
```

### 4. Validate All User Input

```bash
# Bad
threshold="$1"
if [ "$disk_usage" -gt "$threshold" ]; then ...

# Good
threshold="$1"
if ! parrot_validate_percentage "$threshold"; then
    parrot_error "Invalid threshold: $threshold"
    exit 1
fi
```

### 5. Use Configuration Variables

```bash
# Bad
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

# Good
parrot_init_log_dir  # Handles creation and permissions
```

### 6. Enable Debug Mode for Troubleshooting

```bash
# Temporary debug mode
PARROT_DEBUG=true ./my_script.sh

# Or in config.env
PARROT_DEBUG="true"
```

## Security Considerations

### 1. Protect config.env

```bash
chmod 600 rpi-scripts/config.env
```

### 2. Never Commit config.env

The `.gitignore` should include:
```
rpi-scripts/config.env
```

### 3. Use Secure IPC Directory

For production, change from `/tmp`:

```bash
# In config.env
PARROT_IPC_DIR="/run/parrot-mcp"

# Create with proper permissions
sudo mkdir -p /run/parrot-mcp
sudo chown parrot-mcp:parrot-mcp /run/parrot-mcp
sudo chmod 700 /run/parrot-mcp
```

### 4. Enable Strict Permissions

```bash
PARROT_STRICT_PERMS="true"
PARROT_VALIDATION_LEVEL="STRICT"
```

## Troubleshooting

### Configuration Not Loading

**Symptom**: Default values are used instead of config.env values.

**Solution**:
1. Check file location: `rpi-scripts/config.env`
2. Check syntax: `bash -n rpi-scripts/config.env`
3. Enable debug: `PARROT_DEBUG=true ./my_script.sh`

### Permission Errors

**Symptom**: Cannot write to log directory.

**Solution**:
```bash
# Fix log directory permissions
chmod 755 logs/
# Or disable strict permissions temporarily
PARROT_STRICT_PERMS="false" ./my_script.sh
```

### Email Not Sending

**Symptom**: Notifications not received.

**Solution**:
1. Check email configuration:
   ```bash
   echo "${PARROT_ALERT_EMAIL:-}"
   ```
2. Test mail command:
   ```bash
   echo "test" | mail -s "Test" "${PARROT_ALERT_EMAIL:-}"
   ```
3. Check logs:
   ```bash
   tail -f logs/parrot.log
   ```

## Examples

See [examples/](../examples/) directory for complete script examples using the configuration system.

## Related Documentation

- [Security Policy](../SECURITY.md) - Security best practices
- [Logging Standards](LOGGING.md) - Log format specifications
- [Contributing Guidelines](../CONTRIBUTING.md) - Development guidelines

---

**Last Updated**: 2025-11-11
