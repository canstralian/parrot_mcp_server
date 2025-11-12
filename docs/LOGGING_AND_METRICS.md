# Logging and Metrics Guide

This guide explains how to use the logging and metrics system in the Parrot MCP Server.

## Overview

The Parrot MCP Server includes a POSIX-first logging and metrics system with:
- Structured JSON logging to `./logs/parrot.log`
- Prometheus textfile collector metrics in `./metrics/`
- Real-time log streaming via SSE
- Grep-based log search utilities
- Automatic log rotation configuration

## Components

### 1. Structured Logging (`scripts/logging.sh`)

The logging system provides structured JSON logging with automatic sanitization of sensitive data.

#### Basic Usage

```bash
# Source the logging functions
source scripts/logging.sh

# Log an info message
log_info "User logged in" user=alice action=login

# Log an error
log_error "Failed to connect" host=server1 error="Connection timeout"

# Log with sensitive data (automatically redacted)
log_info "API call" api_key=secret123 user=alice
# Output: {..., "api_key":"[REDACTED]", "user":"alice"}
```

#### Available Functions

- `log_info "message" [key=val ...]` - Log info-level message
- `log_error "message" [key=val ...]` - Log error-level message
- `log_warn "message" [key=val ...]` - Log warning message
- `log_debug "message" [key=val ...]` - Log debug message (requires `PARROT_LOG_LEVEL=DEBUG`)
- `log_tool_exec tool user target duration_ms exit_code [extra...]` - Log tool execution

#### Sensitive Data Sanitization

The following field names are automatically redacted:
- `password`, `passwd`, `pwd`
- `token`, `auth_token`
- `secret`
- `api_key`, `apikey`
- `authorization`

### 2. Tool Execution Wrapper (`scripts/wrap_tool_exec.sh`)

Wraps tool execution with automatic logging and metrics collection.

#### Usage

```bash
# Wrap a tool execution
./scripts/wrap_tool_exec.sh <tool_name> <user> <target> <command> [args...]

# Example: Wrap a backup script
./scripts/wrap_tool_exec.sh backup_home alice /home/alice ./scripts/backup_home.sh

# Example: Wrap with arguments
./scripts/wrap_tool_exec.sh system_update root /system apt-get update -y
```

#### Generated Metrics

Metrics are written to `./metrics/<tool_name>.prom` in Prometheus textfile format:

```
# HELP tool_executions_total Total number of tool executions
# TYPE tool_executions_total counter
tool_executions_total{tool="backup_home",status="success"} 42
tool_executions_total{tool="backup_home",status="failure"} 3

# HELP tool_errors_total Total number of tool execution errors
# TYPE tool_errors_total counter
tool_errors_total{tool="backup_home"} 3

# HELP tool_last_duration_ms Duration of last tool execution in milliseconds
# TYPE tool_last_duration_ms gauge
tool_last_duration_ms{tool="backup_home"} 1234

# HELP tool_last_execution_timestamp Unix timestamp of last tool execution
# TYPE tool_last_execution_timestamp gauge
tool_last_execution_timestamp{tool="backup_home"} 1762927865
```

### 3. Log Search (`scripts/search_logs.sh`)

Fast, grep-based log search utility.

#### Usage

```bash
# Search by tool
./scripts/search_logs.sh --tool=backup_home

# Search by user
./scripts/search_logs.sh --user=alice

# Search by status (success or failure)
./scripts/search_logs.sh --status=failure

# Search by log level
./scripts/search_logs.sh --level=ERROR

# Search by date (since)
./scripts/search_logs.sh --since=2024-01-01
./scripts/search_logs.sh --since=2024-01-15T10:00:00

# Combine filters
./scripts/search_logs.sh --tool=backup_home --status=failure --tail=10

# Show last N entries
./scripts/search_logs.sh --tail=50
```

### 4. Real-time Log Streaming (`rpi-scripts/log_stream_sse.py`)

SSE (Server-Sent Events) server for real-time log streaming.

#### Starting the Server

```bash
# Start with defaults (port 8080)
./rpi-scripts/log_stream_sse.py

# Start on custom port
./rpi-scripts/log_stream_sse.py --port=8765

# Specify log file
./rpi-scripts/log_stream_sse.py --log-file=./logs/parrot.log --port=8080
```

#### Endpoints

- `GET /` - Web UI with live log viewer
- `GET /logs/stream` - SSE stream of log entries
- `GET /health` - Health check endpoint

#### Consuming the Stream

**Using curl:**
```bash
curl -N http://localhost:8080/logs/stream
```

**Using JavaScript (browser):**
```javascript
const eventSource = new EventSource('http://localhost:8080/logs/stream');

eventSource.onmessage = (event) => {
    const logEntry = JSON.parse(event.data);
    console.log(logEntry);
};

eventSource.onerror = (error) => {
    console.error('Connection error:', error);
};
```

**Using Python:**
```python
import requests

response = requests.get('http://localhost:8080/logs/stream', stream=True)
for line in response.iter_lines():
    if line:
        print(line.decode('utf-8'))
```

### 5. Log Rotation (`scripts/logrotate_parrot.conf`)

Logrotate configuration for automatic log management.

#### Installation

```bash
# Copy to logrotate directory
sudo cp scripts/logrotate_parrot.conf /etc/logrotate.d/parrot
sudo chown root:root /etc/logrotate.d/parrot
sudo chmod 644 /etc/logrotate.d/parrot

# Test the configuration
sudo logrotate -d /etc/logrotate.d/parrot

# Force rotation (for testing)
sudo logrotate -f /etc/logrotate.d/parrot
```

#### Configuration

- Rotates when log reaches 100M
- Keeps 30 rotated logs
- Compresses old logs with gzip
- Daily rotation schedule
- Uses date suffix (e.g., `parrot.log-20240115`)

## Integration with Prometheus and Grafana

### Prometheus Integration

The metrics files in `./metrics/` are compatible with Prometheus's textfile collector.

#### Option 1: Using node_exporter

```bash
# Configure node_exporter to read textfiles
node_exporter --collector.textfile.directory=/path/to/parrot_mcp_server/metrics

# Add to Prometheus config
scrape_configs:
  - job_name: 'parrot_mcp'
    static_configs:
      - targets: ['localhost:9100']
```

#### Option 2: Custom Exporter

Create a simple exporter that reads and serves the metrics files:

```bash
# Example using Python and prometheus_client
# See Prometheus documentation for details
```

### Grafana Dashboards

Example queries for Grafana:

```promql
# Total executions by tool
sum(tool_executions_total) by (tool)

# Success rate
sum(tool_executions_total{status="success"}) / sum(tool_executions_total)

# Error rate
rate(tool_errors_total[5m])

# Average execution duration
avg(tool_last_duration_ms) by (tool)
```

## For Large Deployments

For production or high-volume deployments, consider:

1. **Log Aggregation**: Ship logs to external aggregator
   - Fluentd
   - Logstash
   - Vector
   - Filebeat

2. **Search and Analytics**: Use centralized log platform
   - Elasticsearch/OpenSearch + Kibana
   - Loki + Grafana
   - Splunk

3. **Metrics**: Use dedicated metrics exporter
   - Prometheus node_exporter with textfile collector
   - Custom exporter reading metrics files
   - Direct instrumentation with prometheus_client

4. **Log Retention**: Configure appropriate retention policies
   - Adjust logrotate settings
   - Configure aggregator retention
   - Set up archival to S3/GCS

## Testing

Run the comprehensive test suite:

```bash
./rpi-scripts/test_logging.sh
```

The test suite validates:
- ✅ Basic JSON logging
- ✅ Sensitive data sanitization
- ✅ Tool wrapper success case with metrics
- ✅ Tool wrapper failure case with error metrics
- ✅ Log search by tool/user/status
- ✅ Metrics accumulation

## Troubleshooting

### Logs not appearing

1. Check log file exists: `ls -la ./logs/parrot.log`
2. Check permissions: `ls -la ./logs/`
3. Verify PARROT_LOG_FILE environment variable
4. Check disk space: `df -h`

### Metrics not updating

1. Check metrics directory: `ls -la ./metrics/`
2. Verify PARROT_METRICS_DIR environment variable
3. Check file permissions
4. Verify tool name is valid (alphanumeric, underscore, dash only)

### SSE server not starting

1. Check port availability: `netstat -tuln | grep 8080`
2. Check Python version: `python3 --version` (requires 3.6+)
3. Check log file path exists
4. Check server output for errors

### Log search returning no results

1. Verify log file location
2. Check filter syntax (use `--help`)
3. Try without filters first
4. Check if logs are in JSON format: `head -1 ./logs/parrot.log | python3 -m json.tool`

## Environment Variables

- `PARROT_LOG_FILE` - Log file path (default: `./logs/parrot.log`)
- `PARROT_METRICS_DIR` - Metrics directory (default: `./metrics`)
- `PARROT_LOG_LEVEL` - Log level (default: `INFO`, set to `DEBUG` for debug logs)

## Security Considerations

1. **Sensitive Data**: Always review logs for sensitive data. The automatic sanitization covers common patterns but may not catch everything.

2. **Log Access**: Restrict access to log files:
   ```bash
   chmod 640 ./logs/parrot.log
   chown user:group ./logs/parrot.log
   ```

3. **Metrics Access**: Metrics files should have restricted permissions in production:
   ```bash
   chmod 640 ./metrics/*.prom
   ```

4. **SSE Server**: In production, run behind a reverse proxy (nginx/Apache) with authentication and TLS.

5. **Log Retention**: Implement appropriate retention policies to comply with data protection regulations.

## Performance Notes

- **Logging**: JSON logging is fast for small to medium volumes. For high-volume logging (>10k logs/sec), consider a dedicated logging library.
- **Metrics**: Textfile collector approach is suitable for cron jobs and periodic tasks. For high-frequency metrics, use direct Prometheus instrumentation.
- **Search**: Grep-based search is fast for files <1GB. For larger log volumes, use Elasticsearch/OpenSearch.
- **Streaming**: SSE server can handle multiple concurrent clients. For production use with many clients, consider using a message queue (Redis Streams, Kafka).

## Examples

See `rpi-scripts/test_logging.sh` for comprehensive examples of all features.
