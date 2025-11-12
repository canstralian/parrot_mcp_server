# Enhanced Logging and Analytics System

## Overview

The Parrot MCP Server includes a comprehensive logging and analytics system built entirely with Bash and standard Unix tools, providing visibility into tool execution, performance metrics, security events, and system health.

## Features

### 1. Structured Logging

#### JSON Logging
All events can be logged in structured JSON format for easy parsing and analysis:

```bash
# Example JSON log entry
{
  "timestamp": "2025-11-12T06:04:23.789Z",
  "level": "INFO",
  "message": "MCP server started",
  "msgid": "1762927463789123456",
  "hostname": "server01",
  "user": "admin",
  "pid": 1234,
  "component": "mcp_server",
  "action": "startup"
}
```

#### Log Levels
- **DEBUG**: Detailed diagnostic information
- **INFO**: General informational messages
- **WARN**: Warning messages for potential issues
- **ERROR**: Error messages for failures
- **CRITICAL**: Critical errors requiring immediate attention

#### Using the Logging API

```bash
# Source the common configuration
source ./common_config.sh

# Text logging
parrot_info "Server started successfully"
parrot_warn "Disk usage above 80%"
parrot_error "Failed to connect to database"
parrot_critical "System out of memory"

# JSON logging with context
parrot_log_json "INFO" "Operation completed" \
    "operation=backup" \
    "duration_ms=1234" \
    "status=success" \
    "files_backed_up=42"
```

### 2. Performance Metrics

#### Collecting Metrics

```bash
# Track operation timing
START=$(parrot_metrics_start)

# ... do some work ...

# Record completion and duration
DURATION=$(parrot_metrics_end "$START" "backup_operation" "success")
echo "Operation took ${DURATION}ms"
```

#### Metrics Export

Metrics are exported in Prometheus text format, compatible with Prometheus scraping:

```bash
# Export metrics in Prometheus format
./scripts/metrics_export.sh --format prometheus

# Export as JSON
./scripts/metrics_export.sh --format json

# Generate human-readable summary
./scripts/metrics_export.sh --format summary
```

Example Prometheus output:
```
# HELP parrot_uptime_seconds System uptime in seconds
# TYPE parrot_uptime_seconds gauge
parrot_uptime_seconds 854

# HELP parrot_operations_total Total number of operations executed
# TYPE parrot_operations_total counter
parrot_operations_total 42

# HELP parrot_success_rate_percent Success rate percentage
# TYPE parrot_success_rate_percent gauge
parrot_success_rate_percent 95.2
```

### 3. Security Audit Trail

All security-relevant operations are logged to a dedicated audit trail:

```bash
# Log an audit event
parrot_audit_log "user_login" "username=admin" "success" \
    "source_ip=192.168.1.100"

# Audit log format (pipe-delimited)
# timestamp|user@hostname|action|target|result
2025-11-12T06:04:23.789Z|admin@server01|user_login|username=admin|success
```

#### Automatic Credential Sanitization

Sensitive data is automatically redacted from logs:

```bash
# This will be sanitized in logs
parrot_log_json "INFO" "User authenticated" \
    "username=admin" \
    "password=secret123"  # Will become password=[REDACTED]

# Sanitize manually
SAFE_VALUE=$(parrot_sanitize_log_value "token=abc123xyz")
# Returns: token=[REDACTED]
```

Patterns automatically sanitized:
- `password=*`, `passwd=*`, `pwd=*`
- `secret=*`, `token=*`, `key=*`
- `api_key=*`, `apikey=*`
- `Bearer <token>`
- `Basic <credentials>`

### 4. Log Search and Filtering

Search logs with multiple criteria:

```bash
# Search for errors
./scripts/log_search.sh --level ERROR --format text

# Search by user
./scripts/log_search.sh --user admin --format json

# Search by time range
./scripts/log_search.sh \
    --since "2025-11-12 00:00:00" \
    --until "2025-11-12 23:59:59" \
    --format csv

# Complex search
./scripts/log_search.sh \
    --level ERROR \
    --status error \
    --since "2025-11-12" \
    --output /tmp/errors.json \
    --format json
```

### 5. Log Rotation

Automatic log rotation based on size and age:

```bash
# Rotate logs larger than 100MB
./scripts/log_rotate.sh --size 100

# Keep logs for 30 days
./scripts/log_rotate.sh --age 30

# Keep only 5 rotated versions
./scripts/log_rotate.sh --count 5

# Combined
./scripts/log_rotate.sh --size 100 --age 30 --count 5
```

Logs are automatically:
- Compressed with gzip
- Timestamped
- Limited by retention policy

### 6. Metrics Dashboard

Generate an HTML dashboard with real-time metrics:

```bash
# Generate dashboard
./scripts/dashboard_generate.sh

# Custom output location
./scripts/dashboard_generate.sh --output /var/www/html/metrics.html

# Auto-refresh every 30 seconds
./scripts/dashboard_generate.sh --refresh 30
```

Dashboard includes:
- System status and health
- Uptime statistics
- Success/failure rates
- Operation latency (avg, P95, P99)
- Recent errors
- Recent audit events

## Configuration

Configure logging behavior in `config.env`:

```bash
# Log levels: DEBUG, INFO, WARN, ERROR, CRITICAL
PARROT_LOG_LEVEL="INFO"

# Log format: text or json
PARROT_LOG_FORMAT="text"

# Log file locations
PARROT_SERVER_LOG="/path/to/parrot.log"
PARROT_JSON_LOG="/path/to/parrot.json.log"
PARROT_AUDIT_LOG="/path/to/audit.log"
PARROT_METRICS_LOG="/path/to/metrics.log"

# Rotation settings
PARROT_LOG_MAX_SIZE="100M"     # Max size before rotation
PARROT_LOG_MAX_AGE="30"        # Days to keep logs
PARROT_LOG_ROTATION_COUNT="5"  # Number of rotated files to keep
```

## Integration Examples

### Script Integration

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/common_config.sh"

# Start timing
START=$(parrot_metrics_start)

# Log start
parrot_info "Starting backup process"
parrot_audit_log "backup_start" "/data" "initiated"

# Do work
if perform_backup; then
    STATUS="success"
    parrot_info "Backup completed successfully"
else
    STATUS="error"
    parrot_error "Backup failed"
fi

# Record metrics and audit
parrot_metrics_end "$START" "backup" "$STATUS"
parrot_audit_log "backup_complete" "/data" "$STATUS"
```

### Monitoring Integration

```bash
# Export metrics for Prometheus
./scripts/metrics_export.sh --format prometheus > /var/lib/prometheus/node_exporter/parrot_metrics.prom

# Generate dashboard for web server
./scripts/dashboard_generate.sh --output /var/www/html/metrics.html --refresh 30
```

### Cron Integration

```bash
# Add to crontab for automatic rotation
0 2 * * * /path/to/scripts/log_rotate.sh --size 100 --age 30 --count 5

# Generate dashboard every 5 minutes
*/5 * * * * /path/to/scripts/dashboard_generate.sh --output /var/www/html/metrics.html
```

## Performance Considerations

- **Overhead**: Logging overhead is < 5% of execution time for typical operations
- **Log Rotation**: Automatic rotation prevents disk space issues
- **Search Performance**: Log searches complete in < 1 second for files up to 100MB
- **Concurrent Logging**: Safe for concurrent operations (atomic writes)

## Troubleshooting

### Logs Not Appearing

Check log file permissions:
```bash
ls -la /path/to/logs/
chmod 700 /path/to/logs/  # If needed
```

Check log level configuration:
```bash
echo $PARROT_LOG_LEVEL
# Set to DEBUG for maximum verbosity
export PARROT_LOG_LEVEL="DEBUG"
```

### JSON Parsing Errors

Validate JSON log file:
```bash
jq empty /path/to/parrot.json.log
```

### Disk Space Issues

Check log sizes and rotate:
```bash
du -sh /path/to/logs/*
./scripts/log_rotate.sh --size 10 --count 3
```

## Best Practices

1. **Use appropriate log levels**: DEBUG for development, INFO for production
2. **Sanitize sensitive data**: Always use `parrot_sanitize_log_value` for user input
3. **Include context**: Add relevant key=value pairs to JSON logs
4. **Monitor metrics**: Regularly check success rates and error counts
5. **Automate rotation**: Set up cron jobs for log rotation
6. **Archive audit logs**: Keep audit logs longer than general logs for compliance

## API Reference

### Logging Functions

- `parrot_log LEVEL "message"` - Log a message at specified level
- `parrot_debug "message"` - Log DEBUG message
- `parrot_info "message"` - Log INFO message
- `parrot_warn "message"` - Log WARN message
- `parrot_error "message"` - Log ERROR message
- `parrot_critical "message"` - Log CRITICAL message
- `parrot_log_json LEVEL "message" [key=value...]` - Log structured JSON

### Metrics Functions

- `parrot_metrics_start` - Start timing (returns timestamp)
- `parrot_metrics_end START_TIME "operation" "status" [context...]` - End timing and log

### Audit Functions

- `parrot_audit_log "action" "target" "result" [context...]` - Log audit event

### Utility Functions

- `parrot_sanitize_log_value "value"` - Sanitize sensitive data
- `parrot_sanitize_input "input"` - Sanitize general input

## See Also

- [Usage Guide](USAGE.md)
- [Testing Guide](../TESTING.md)
- [Security Documentation](../SECURITY.md)
