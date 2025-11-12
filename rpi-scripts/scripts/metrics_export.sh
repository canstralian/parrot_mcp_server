#!/usr/bin/env bash
# metrics_export.sh - Export metrics in Prometheus text format
# Usage: ./metrics_export.sh [--output FILE] [--format prometheus|json|summary]

set -euo pipefail

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

OUTPUT_FILE=""
OUTPUT_FORMAT="prometheus"

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Export performance metrics in various formats.

Options:
  --output FILE       Output to file instead of stdout
  --format FORMAT     Output format: prometheus (default), json, summary
  --help, -h          Show this help message

Formats:
  prometheus  - Prometheus text format (compatible with Prometheus scraping)
  json        - JSON format with aggregated statistics
  summary     - Human-readable summary

Examples:
  # Export in Prometheus format
  $0 --format prometheus

  # Generate summary report
  $0 --format summary

  # Export to file
  $0 --output /tmp/metrics.txt
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Function to calculate metrics from logs
calculate_metrics() {
    if [ ! -f "$PARROT_JSON_LOG" ]; then
        parrot_warn "JSON log file not found: $PARROT_JSON_LOG"
        return 1
    fi

    # Calculate metrics using jq
    local uptime_seconds
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)

    local total_operations
    total_operations=$(jq -r 'select(.operation != null) | 1' "$PARROT_JSON_LOG" 2>/dev/null | wc -l || echo 0)

    local successful_operations
    successful_operations=$(jq -r 'select(.operation != null and .status == "success") | 1' "$PARROT_JSON_LOG" 2>/dev/null | wc -l || echo 0)

    local failed_operations
    failed_operations=$(jq -r 'select(.operation != null and .status != "success") | 1' "$PARROT_JSON_LOG" 2>/dev/null | wc -l || echo 0)

    local error_count
    error_count=$(jq -r 'select(.level == "ERROR" or .level == "CRITICAL") | 1' "$PARROT_JSON_LOG" 2>/dev/null | wc -l || echo 0)

    # Calculate success rate
    local success_rate=0
    if [ "$total_operations" -gt 0 ]; then
        success_rate=$(awk "BEGIN {printf \"%.2f\", ($successful_operations / $total_operations) * 100}")
    fi

    # Calculate average, min, max duration
    local avg_duration min_duration max_duration p95_duration p99_duration
    if [ "$total_operations" -gt 0 ]; then
        avg_duration=$(jq -r 'select(.duration_ms != null) | .duration_ms' "$PARROT_JSON_LOG" 2>/dev/null | \
            awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print 0}')
        min_duration=$(jq -r 'select(.duration_ms != null) | .duration_ms' "$PARROT_JSON_LOG" 2>/dev/null | \
            sort -n | head -1 || echo 0)
        max_duration=$(jq -r 'select(.duration_ms != null) | .duration_ms' "$PARROT_JSON_LOG" 2>/dev/null | \
            sort -n | tail -1 || echo 0)
        
        # Calculate percentiles
        local durations_file
        durations_file=$(mktemp)
        jq -r 'select(.duration_ms != null) | .duration_ms' "$PARROT_JSON_LOG" 2>/dev/null | sort -n >"$durations_file"
        local count
        count=$(wc -l <"$durations_file")
        if [ "$count" -gt 0 ]; then
            p95_duration=$(awk -v count="$count" 'NR == int(count * 0.95) + 1 {print; exit}' "$durations_file" || echo 0)
            p99_duration=$(awk -v count="$count" 'NR == int(count * 0.99) + 1 {print; exit}' "$durations_file" || echo 0)
        else
            p95_duration=0
            p99_duration=0
        fi
        rm -f "$durations_file"
    else
        avg_duration=0
        min_duration=0
        max_duration=0
        p95_duration=0
        p99_duration=0
    fi

    # Export based on format
    case "$OUTPUT_FORMAT" in
        prometheus)
            cat <<EOF
# HELP parrot_uptime_seconds System uptime in seconds
# TYPE parrot_uptime_seconds gauge
parrot_uptime_seconds $uptime_seconds

# HELP parrot_operations_total Total number of operations executed
# TYPE parrot_operations_total counter
parrot_operations_total $total_operations

# HELP parrot_operations_success Total number of successful operations
# TYPE parrot_operations_success counter
parrot_operations_success $successful_operations

# HELP parrot_operations_failed Total number of failed operations
# TYPE parrot_operations_failed counter
parrot_operations_failed $failed_operations

# HELP parrot_success_rate_percent Success rate percentage
# TYPE parrot_success_rate_percent gauge
parrot_success_rate_percent $success_rate

# HELP parrot_errors_total Total number of errors logged
# TYPE parrot_errors_total counter
parrot_errors_total $error_count

# HELP parrot_operation_duration_avg_ms Average operation duration in milliseconds
# TYPE parrot_operation_duration_avg_ms gauge
parrot_operation_duration_avg_ms $avg_duration

# HELP parrot_operation_duration_min_ms Minimum operation duration in milliseconds
# TYPE parrot_operation_duration_min_ms gauge
parrot_operation_duration_min_ms $min_duration

# HELP parrot_operation_duration_max_ms Maximum operation duration in milliseconds
# TYPE parrot_operation_duration_max_ms gauge
parrot_operation_duration_max_ms $max_duration

# HELP parrot_operation_duration_p95_ms 95th percentile operation duration in milliseconds
# TYPE parrot_operation_duration_p95_ms gauge
parrot_operation_duration_p95_ms $p95_duration

# HELP parrot_operation_duration_p99_ms 99th percentile operation duration in milliseconds
# TYPE parrot_operation_duration_p99_ms gauge
parrot_operation_duration_p99_ms $p99_duration
EOF
            ;;
        json)
            cat <<EOF
{
  "uptime_seconds": $uptime_seconds,
  "operations": {
    "total": $total_operations,
    "successful": $successful_operations,
    "failed": $failed_operations,
    "success_rate_percent": $success_rate
  },
  "errors": {
    "total": $error_count
  },
  "duration_ms": {
    "avg": $avg_duration,
    "min": $min_duration,
    "max": $max_duration,
    "p95": $p95_duration,
    "p99": $p99_duration
  }
}
EOF
            ;;
        summary)
            cat <<EOF
=== Parrot MCP Server Metrics Summary ===

System Information:
  Uptime:              ${uptime_seconds}s ($(awk "BEGIN {printf \"%.1fh\", $uptime_seconds/3600}"))
  
Operations:
  Total:               $total_operations
  Successful:          $successful_operations
  Failed:              $failed_operations
  Success Rate:        ${success_rate}%

Errors:
  Total Errors:        $error_count

Performance (Duration in ms):
  Average:             $avg_duration
  Minimum:             $min_duration
  Maximum:             $max_duration
  95th Percentile:     $p95_duration
  99th Percentile:     $p99_duration

=========================================
EOF
            ;;
        *)
            parrot_error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# Execute metrics calculation and output
if [ -n "$OUTPUT_FILE" ]; then
    calculate_metrics >"$OUTPUT_FILE"
    parrot_info "Metrics written to: $OUTPUT_FILE"
else
    calculate_metrics
fi

parrot_audit_log "metrics_export" "format=$OUTPUT_FORMAT" "success"
