#!/usr/bin/env bash
# dashboard_generate.sh - Generate HTML dashboard from metrics
# Usage: ./dashboard_generate.sh [--output FILE] [--refresh SECONDS]

set -euo pipefail

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

OUTPUT_FILE="${PARROT_LOG_DIR}/dashboard.html"
REFRESH_INTERVAL=30

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --refresh)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [options]

Generate HTML dashboard from metrics.

Options:
  --output FILE       Output HTML file (default: logs/dashboard.html)
  --refresh SECONDS   Auto-refresh interval in seconds (default: 30, 0 to disable)
  --help, -h          Show this help message

Examples:
  # Generate dashboard with default settings
  $0

  # Generate dashboard with 60-second refresh
  $0 --refresh 60

  # Generate dashboard to custom location
  $0 --output /var/www/html/metrics.html
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Get metrics data
METRICS_JSON=$(cd "$SCRIPT_DIR/scripts" && ./metrics_export.sh --format json 2>/dev/null || echo '{}')

# Get recent errors
RECENT_ERRORS=$(jq -r 'select(.level == "ERROR" or .level == "CRITICAL") | [.timestamp, .level, .message] | @tsv' "$PARROT_JSON_LOG" 2>/dev/null | tail -10 | \
    awk -F'\t' '{printf "<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n", $1, $2, $3}' || echo "<tr><td colspan='3'>No errors found</td></tr>")

# Get recent audit events
RECENT_AUDIT=$(tail -10 "$PARROT_AUDIT_LOG" 2>/dev/null | \
    awk -F'|' '{printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", $1, $2, $3, $5}' || echo "<tr><td colspan='4'>No audit events found</td></tr>")

# Extract metrics from JSON
UPTIME=$(echo "$METRICS_JSON" | jq -r '.uptime_seconds // 0')
UPTIME_HOURS=$(awk "BEGIN {printf \"%.1f\", $UPTIME/3600}")
TOTAL_OPS=$(echo "$METRICS_JSON" | jq -r '.operations.total // 0')
SUCCESS_OPS=$(echo "$METRICS_JSON" | jq -r '.operations.successful // 0')
FAILED_OPS=$(echo "$METRICS_JSON" | jq -r '.operations.failed // 0')
SUCCESS_RATE=$(echo "$METRICS_JSON" | jq -r '.operations.success_rate_percent // 0')
TOTAL_ERRORS=$(echo "$METRICS_JSON" | jq -r '.errors.total // 0')
AVG_DURATION=$(echo "$METRICS_JSON" | jq -r '.duration_ms.avg // 0')
P95_DURATION=$(echo "$METRICS_JSON" | jq -r '.duration_ms.p95 // 0')
P99_DURATION=$(echo "$METRICS_JSON" | jq -r '.duration_ms.p99 // 0')

# Determine health status
HEALTH_STATUS="Healthy"
HEALTH_COLOR="green"
if [ "$(echo "$SUCCESS_RATE < 90" | bc -l 2>/dev/null || echo 0)" -eq 1 ] || [ "$TOTAL_ERRORS" -gt 10 ]; then
    HEALTH_STATUS="Warning"
    HEALTH_COLOR="orange"
fi
if [ "$(echo "$SUCCESS_RATE < 70" | bc -l 2>/dev/null || echo 0)" -eq 1 ] || [ "$TOTAL_ERRORS" -gt 50 ]; then
    HEALTH_STATUS="Critical"
    HEALTH_COLOR="red"
fi

# Generate HTML dashboard
cat >"$OUTPUT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Parrot MCP Server - Dashboard</title>
    $([ "$REFRESH_INTERVAL" -gt 0 ] && echo "<meta http-equiv=\"refresh\" content=\"$REFRESH_INTERVAL\">")
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: #f5f5f5;
            padding: 20px;
            color: #333;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        h1 { font-size: 2em; margin-bottom: 10px; }
        .subtitle { opacity: 0.9; font-size: 0.9em; }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: white;
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        .metric-card.success { border-left-color: #48bb78; }
        .metric-card.warning { border-left-color: #ed8936; }
        .metric-card.error { border-left-color: #f56565; }
        .metric-label {
            color: #718096;
            font-size: 0.85em;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }
        .metric-value {
            font-size: 2.5em;
            font-weight: bold;
            color: #2d3748;
        }
        .metric-unit {
            font-size: 0.5em;
            color: #718096;
            font-weight: normal;
        }
        .health-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
            color: white;
            background: $HEALTH_COLOR;
        }
        .section {
            background: white;
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .section h2 {
            font-size: 1.5em;
            margin-bottom: 20px;
            color: #2d3748;
            border-bottom: 2px solid #e2e8f0;
            padding-bottom: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
        }
        th {
            background: #f7fafc;
            font-weight: 600;
            color: #4a5568;
            font-size: 0.85em;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        tr:hover { background: #f7fafc; }
        .footer {
            text-align: center;
            color: #718096;
            font-size: 0.85em;
            margin-top: 30px;
            padding: 20px;
        }
        .timestamp {
            color: #718096;
            font-size: 0.85em;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🦜 Parrot MCP Server Dashboard</h1>
            <div class="subtitle">Real-time monitoring and analytics</div>
            <div class="subtitle timestamp">Last updated: $(date '+%Y-%m-%d %H:%M:%S')</div>
        </header>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">System Status</div>
                <div class="metric-value">
                    <span class="health-badge">$HEALTH_STATUS</span>
                </div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Uptime</div>
                <div class="metric-value">$UPTIME_HOURS <span class="metric-unit">hours</span></div>
            </div>
            <div class="metric-card success">
                <div class="metric-label">Success Rate</div>
                <div class="metric-value">$(printf "%.1f" "$SUCCESS_RATE") <span class="metric-unit">%</span></div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Total Operations</div>
                <div class="metric-value">$TOTAL_OPS</div>
            </div>
            <div class="metric-card success">
                <div class="metric-label">Successful</div>
                <div class="metric-value">$SUCCESS_OPS</div>
            </div>
            <div class="metric-card error">
                <div class="metric-label">Failed</div>
                <div class="metric-value">$FAILED_OPS</div>
            </div>
            <div class="metric-card error">
                <div class="metric-label">Total Errors</div>
                <div class="metric-value">$TOTAL_ERRORS</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Avg Duration</div>
                <div class="metric-value">$(printf "%.0f" "$AVG_DURATION") <span class="metric-unit">ms</span></div>
            </div>
            <div class="metric-card warning">
                <div class="metric-label">P95 Duration</div>
                <div class="metric-value">$(printf "%.0f" "$P95_DURATION") <span class="metric-unit">ms</span></div>
            </div>
            <div class="metric-card warning">
                <div class="metric-label">P99 Duration</div>
                <div class="metric-value">$(printf "%.0f" "$P99_DURATION") <span class="metric-unit">ms</span></div>
            </div>
        </div>

        <div class="section">
            <h2>Recent Errors</h2>
            <table>
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Level</th>
                        <th>Message</th>
                    </tr>
                </thead>
                <tbody>
                    $RECENT_ERRORS
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>Recent Audit Events</h2>
            <table>
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>User</th>
                        <th>Action</th>
                        <th>Result</th>
                    </tr>
                </thead>
                <tbody>
                    $RECENT_AUDIT
                </tbody>
            </table>
        </div>

        <div class="footer">
            <p>Parrot MCP Server - Enhanced Logging and Analytics System</p>
            <p>Auto-refresh: $([ "$REFRESH_INTERVAL" -gt 0 ] && echo "${REFRESH_INTERVAL}s" || echo "Disabled")</p>
        </div>
    </div>
</body>
</html>
EOF

parrot_info "Dashboard generated: $OUTPUT_FILE"
parrot_audit_log "dashboard_generate" "output=$OUTPUT_FILE" "success"

echo "Dashboard generated successfully: $OUTPUT_FILE"
