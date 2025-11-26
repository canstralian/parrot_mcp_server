# Rate Limiter Documentation

## Overview

The Parrot MCP Server includes a robust rate limiting implementation to protect against abuse and ensure fair resource usage. The rate limiter tracks operations per user and operation type within a configurable time window.

## Features

- **Per-user, per-operation tracking**: Different users and operation types are tracked independently
- **Time-windowed limits**: Only entries within the configured time window count toward the limit
- **Automatic cleanup**: Old entries are automatically removed during rate limit checks
- **Atomic operations**: Thread-safe file operations prevent race conditions
- **Input sanitization**: User and operation names are sanitized to prevent injection attacks
- **Configurable**: Limits and time windows can be adjusted via environment variables

## Configuration

The following environment variables control rate limiting behavior:

| Variable | Default | Description |
|----------|---------|-------------|
| `PARROT_RATE_LIMIT` | 100 | Maximum operations per user per operation type within the time window |
| `PARROT_RATE_LIMIT_WINDOW` | 3600 | Time window in seconds (default: 1 hour) |
| `PARROT_RATE_LIMIT_FILE` | `${PARROT_LOG_DIR}/rate_limit.log` | File path for rate limit history |

### Example Configuration

```bash
# config.env
PARROT_RATE_LIMIT=50           # Allow 50 operations per hour
PARROT_RATE_LIMIT_WINDOW=1800  # Use 30-minute window
```

## Usage

### Basic Usage

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/common_config.sh"

# Check if user is within rate limit
if parrot_check_rate_limit "username" "operation_name"; then
    # Rate limit OK - perform the operation
    perform_operation
else
    # Rate limit exceeded
    echo "ERROR: Rate limit exceeded. Please try again later."
    exit 1
fi
```

### Example Script

See `rpi-scripts/scripts/example_rate_limited_scan.sh` for a complete example:

```bash
# Run the example with default user
./rpi-scripts/scripts/example_rate_limited_scan.sh

# Run with specific user
./rpi-scripts/scripts/example_rate_limited_scan.sh alice

# Test rate limiting with low limit
PARROT_RATE_LIMIT=3 ./rpi-scripts/scripts/example_rate_limited_scan.sh alice
```

## Implementation Details

### How It Works

1. **Input validation and sanitization**: User and operation names are validated and sanitized
2. **File creation**: Rate limit file is created with secure permissions (600) if it doesn't exist
3. **Timestamp calculation**: Current timestamp and cutoff time are calculated
4. **Cleanup and counting**: An awk script processes the rate limit file to:
   - Remove entries older than the cutoff time
   - Count matching entries for the user and operation
   - Write back only recent entries
5. **Rate limit check**: If the count is at or above the limit, the check fails
6. **Entry addition**: If the check passes, a new entry is added to the file
7. **Atomic update**: The temp file is atomically moved to replace the rate limit file

### File Format

The rate limit file uses a simple colon-separated format:

```
user:operation:timestamp
user:operation:timestamp
...
```

Example:
```
alice:scan:1763546415
bob:read:1763546420
alice:scan:1763546425
```

### Algorithm Correctness

The implementation avoids the common bug of deleting all user records before counting:

❌ **Buggy approach** (deletes all records):
```bash
# This is WRONG - deletes ALL user records
sed -i "/^${user}:${operation}:[0-9]*$/d" "$RATE_LIMIT_FILE"
# Now counting always returns 0!
count=$(grep -c "^${user}:${operation}:" "$RATE_LIMIT_FILE")
```

✅ **Correct approach** (only deletes old records):
```bash
# This is CORRECT - only removes entries older than cutoff
awk -v cutoff="$cutoff" '{
    split($0, parts, ":")
    if (parts[3] >= cutoff) {
        print $0  # Keep recent entries
    }
}' "$RATE_LIMIT_FILE"
```

### Performance Characteristics

- **Time complexity**: O(n) where n is the number of entries in the rate limit file
- **Space complexity**: O(n) for temporary file during cleanup
- **I/O operations**: One read, one write per rate limit check
- **Cleanup frequency**: Every rate limit check cleans up old entries for all users

### Security Considerations

1. **Input sanitization**: User and operation names are sanitized to allow only alphanumeric characters, underscores, and hyphens
2. **File permissions**: Rate limit file is created with mode 600 (owner read/write only)
3. **Atomic operations**: Temporary files and `mv` ensure thread-safe updates
4. **No shell injection**: All user inputs are sanitized before use in shell commands
5. **Directory creation**: Log directory is created with appropriate permissions if it doesn't exist

## Testing

The rate limiter includes comprehensive BATS tests:

```bash
# Run rate limiter tests
bats rpi-scripts/tests/rate_limiter.bats
```

### Test Coverage

- Creates rate limit file if it doesn't exist
- Allows operations within limit
- Blocks operations exceeding limit
- Tracks different users independently
- Tracks different operations independently
- Cleans up old entries
- Preserves recent entries while cleaning old ones
- Sanitizes user and operation inputs
- Requires both user and operation parameters
- Handles concurrent access safely
- Counts entries correctly after cleanup

## Troubleshooting

### Rate Limit Not Working

1. Check if the rate limit file is writable:
   ```bash
   ls -la "$PARROT_LOG_DIR/rate_limit.log"
   ```

2. Verify configuration:
   ```bash
   echo "Limit: $PARROT_RATE_LIMIT"
   echo "Window: $PARROT_RATE_LIMIT_WINDOW seconds"
   ```

3. Check for old entries:
   ```bash
   cat "$PARROT_LOG_DIR/rate_limit.log"
   ```

### Debugging

Enable debug logging to see rate limit checks:

```bash
export PARROT_DEBUG=true
export PARROT_LOG_LEVEL=DEBUG
./rpi-scripts/scripts/example_rate_limited_scan.sh testuser
```

### Resetting Rate Limits

To reset rate limits for all users:

```bash
rm -f "$PARROT_LOG_DIR/rate_limit.log"
```

To reset rate limits for a specific user:

```bash
# Remove entries for specific user
sed -i "/^username:/d" "$PARROT_LOG_DIR/rate_limit.log"
```

## Best Practices

1. **Choose appropriate limits**: Set `PARROT_RATE_LIMIT` based on expected usage patterns
2. **Monitor the rate limit file**: Watch file size to ensure cleanup is working
3. **Use specific operation names**: Use descriptive operation names like "scan", "read", "write"
4. **Handle failures gracefully**: Always check the return value and provide user feedback
5. **Log rate limit violations**: Use `parrot_warn` or `parrot_error` to log violations

## Examples

### Protecting an API Endpoint

```bash
handle_request() {
    local user="$1"
    local endpoint="$2"
    
    # Check rate limit
    if ! parrot_check_rate_limit "$user" "$endpoint"; then
        echo '{"error":"Rate limit exceeded","retry_after":3600}'
        return 1
    fi
    
    # Process request
    process_api_request "$user" "$endpoint"
}
```

### Different Limits for Different Operations

```bash
# Set different limits based on operation
case "$operation" in
    "scan")
        export PARROT_RATE_LIMIT=10  # 10 scans per hour
        ;;
    "read")
        export PARROT_RATE_LIMIT=100  # 100 reads per hour
        ;;
    "write")
        export PARROT_RATE_LIMIT=50   # 50 writes per hour
        ;;
esac

parrot_check_rate_limit "$user" "$operation"
```

### Admin Bypass

```bash
# Allow admins to bypass rate limits
if [ "$user" != "admin" ]; then
    if ! parrot_check_rate_limit "$user" "$operation"; then
        echo "ERROR: Rate limit exceeded"
        exit 1
    fi
fi

perform_operation
```

## Future Enhancements

Potential improvements for future releases:

- [ ] Per-IP rate limiting for network operations
- [ ] Different limits for different user tiers (basic, premium, etc.)
- [ ] Rate limit statistics and reporting
- [ ] Automatic rate limit adjustment based on load
- [ ] Redis or database backend for distributed rate limiting
- [ ] Grace period for first-time users
- [ ] Rate limit headers in responses (X-RateLimit-Limit, X-RateLimit-Remaining, etc.)

## References

- Common configuration: `rpi-scripts/common_config.sh`
- Example script: `rpi-scripts/scripts/example_rate_limited_scan.sh`
- Tests: `rpi-scripts/tests/rate_limiter.bats`
- Security guide: `docs/IPC_SECURITY.md`

---

**Last Updated**: 2025-11-19
