# SARIF Usage Examples

This guide provides practical examples of using the SARIF ABI Contract implementation in various workflows.

## Quick Start

### Basic Scan

Scan a single script for security issues:

```bash
./cli.sh sarif_scanner file myScript.sh output.sarif
```

Scan an entire directory:

```bash
./cli.sh sarif_scanner scan ./scripts output.sarif
```

### View Results

Using jq to view findings in a readable format:

```bash
# View all findings
jq '.runs[0].results[] | {
  rule: .ruleId,
  level: .level,
  message: .message.text,
  file: .locations[0].physicalLocation.artifactLocation.uri,
  line: .locations[0].physicalLocation.region.startLine
}' output.sarif

# Count findings by severity
jq '.runs[0].results | group_by(.level) | 
    map({level: .[0].level, count: length})' output.sarif

# List unique rules triggered
jq -r '.runs[0].results[].ruleId | unique' output.sarif | sort -u
```

## Real-World Workflows

### Pre-Commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Pre-commit hook to scan staged shell scripts

set -e

# Get list of staged .sh files
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' || true)

if [ -z "$staged_files" ]; then
    echo "No shell scripts to scan"
    exit 0
fi

echo "Running SARIF security scan..."

# Create temporary directory for scan
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Scan each file
for file in $staged_files; do
    if [ -f "$file" ]; then
        ./rpi-scripts/scripts/sarif_scanner.sh file "$file" "$tmpdir/$(basename "$file").sarif"
    fi
done

# Check for critical/error findings
critical_count=0
for sarif in "$tmpdir"/*.sarif; do
    count=$(jq '[.runs[0].results[] | select(.level == "error")] | length' "$sarif")
    critical_count=$((critical_count + count))
done

if [ "$critical_count" -gt 0 ]; then
    echo "❌ Found $critical_count critical security issue(s)"
    echo "Review findings in SARIF output and fix before committing"
    exit 1
else
    echo "✓ Security scan passed"
    exit 0
fi
```

Make it executable:

```bash
chmod +x .git/hooks/pre-commit
```

### CI/CD Integration

#### GitHub Actions

Create `.github/workflows/sarif-scan.yml`:

```yaml
name: SARIF Security Scan

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Scan shell scripts
        run: |
          chmod +x rpi-scripts/scripts/*.sh
          ./rpi-scripts/scripts/sarif_scanner.sh scan ./rpi-scripts output.sarif
      
      - name: Validate SARIF output
        run: |
          ./rpi-scripts/scripts/sarif_validator.sh validate output.sarif
      
      - name: Upload SARIF to GitHub Code Scanning
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: output.sarif
          category: shell-security
      
      - name: Check for critical findings
        run: |
          critical=$(jq '[.runs[0].results[] | select(.level == "error")] | length' output.sarif)
          if [ "$critical" -gt 0 ]; then
            echo "Found $critical critical issues"
            exit 1
          fi
```

#### GitLab CI

Create `.gitlab-ci.yml`:

```yaml
sarif_scan:
  stage: test
  script:
    - chmod +x rpi-scripts/scripts/*.sh
    - ./rpi-scripts/scripts/sarif_scanner.sh scan ./rpi-scripts sarif-output.json
    - ./rpi-scripts/scripts/sarif_validator.sh validate sarif-output.json
  artifacts:
    reports:
      sast: sarif-output.json
    paths:
      - sarif-output.json
    expire_in: 1 week
```

### Continuous Monitoring

#### Daily Scan Script

Create `scripts/daily_sarif_scan.sh`:

```bash
#!/usr/bin/env bash
# Daily security scan with email notification

set -euo pipefail

SCAN_DIR="/opt/my-scripts"
OUTPUT_DIR="/var/log/sarif-scans"
DATE=$(date +%Y-%m-%d)
OUTPUT_FILE="${OUTPUT_DIR}/scan-${DATE}.sarif"

mkdir -p "$OUTPUT_DIR"

echo "Starting daily SARIF scan at $(date)"

# Run scan
./rpi-scripts/scripts/sarif_scanner.sh scan "$SCAN_DIR" "$OUTPUT_FILE"

# Validate output
./rpi-scripts/scripts/sarif_validator.sh validate "$OUTPUT_FILE"

# Generate summary
total=$(jq '.runs[0].results | length' "$OUTPUT_FILE")
errors=$(jq '[.runs[0].results[] | select(.level == "error")] | length' "$OUTPUT_FILE")
warnings=$(jq '[.runs[0].results[] | select(.level == "warning")] | length' "$OUTPUT_FILE")

echo "Scan complete: $total findings ($errors errors, $warnings warnings)"

# Send email if critical issues found
if [ "$errors" -gt 0 ]; then
    {
        echo "Security Scan Alert - $(date)"
        echo ""
        echo "Found $errors critical security issue(s)"
        echo ""
        echo "Details:"
        jq -r '.runs[0].results[] | select(.level == "error") | 
               "- \(.ruleId): \(.message.text) in \(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine)"' "$OUTPUT_FILE"
        echo ""
        echo "Full report: $OUTPUT_FILE"
    } | mail -s "Security Alert: $errors critical issues" security-team@example.com
fi

# Rotate old scans (keep last 30 days)
find "$OUTPUT_DIR" -name "scan-*.sarif" -mtime +30 -delete

echo "Scan completed at $(date)"
```

Add to crontab:

```bash
0 2 * * * /path/to/scripts/daily_sarif_scan.sh >> /var/log/sarif-cron.log 2>&1
```

### Development Workflow

#### Interactive Scan and Fix

```bash
#!/usr/bin/env bash
# Interactive scan-fix workflow

scan_and_review() {
    local target="${1:-.}"
    local output="/tmp/sarif-scan.json"
    
    echo "Scanning $target..."
    ./rpi-scripts/scripts/sarif_scanner.sh scan "$target" "$output"
    
    echo ""
    echo "=== Scan Results ==="
    
    # Show summary
    total=$(jq '.runs[0].results | length' "$output")
    echo "Total findings: $total"
    
    # Group by severity
    jq -r '.runs[0].results | group_by(.level) | 
           .[] | "\(.[0].level): \(length)"' "$output"
    
    echo ""
    echo "=== Details ==="
    
    # Show each finding with context
    jq -r '.runs[0].results[] | 
           "[\(.level | ascii_upcase)] \(.ruleId) at \(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine)\n  \(.message.text)\n"' "$output"
    
    echo ""
    echo "Full report saved to: $output"
    echo ""
    echo "To view in your editor:"
    echo "  jq . $output | less"
}

# Usage
scan_and_review "${1:-.}"
```

### Baseline and Comparison

Track security posture over time:

```bash
#!/usr/bin/env bash
# Create baseline and compare future scans

create_baseline() {
    local target="$1"
    local baseline="./sarif-baseline.json"
    
    echo "Creating baseline..."
    ./rpi-scripts/scripts/sarif_scanner.sh scan "$target" "$baseline"
    
    echo "Baseline created: $baseline"
    echo "Fingerprints saved for future comparison"
}

compare_to_baseline() {
    local target="$1"
    local baseline="./sarif-baseline.json"
    local current="/tmp/sarif-current.json"
    
    if [ ! -f "$baseline" ]; then
        echo "No baseline found. Create one with: create_baseline"
        exit 1
    fi
    
    echo "Scanning current state..."
    ./rpi-scripts/scripts/sarif_scanner.sh scan "$target" "$current"
    
    echo ""
    echo "=== Comparison ==="
    
    # Extract fingerprints
    jq -r '.runs[0].results[].partialFingerprints.primaryLocationLineHash' "$baseline" | sort > /tmp/baseline-fps.txt
    jq -r '.runs[0].results[].partialFingerprints.primaryLocationLineHash' "$current" | sort > /tmp/current-fps.txt
    
    # New findings
    new_count=$(comm -13 /tmp/baseline-fps.txt /tmp/current-fps.txt | wc -l)
    echo "New findings: $new_count"
    
    # Fixed findings
    fixed_count=$(comm -23 /tmp/baseline-fps.txt /tmp/current-fps.txt | wc -l)
    echo "Fixed findings: $fixed_count"
    
    # Unchanged
    unchanged_count=$(comm -12 /tmp/baseline-fps.txt /tmp/current-fps.txt | wc -l)
    echo "Unchanged findings: $unchanged_count"
    
    if [ "$new_count" -gt 0 ]; then
        echo ""
        echo "New findings details:"
        # Get new fingerprints
        comm -13 /tmp/baseline-fps.txt /tmp/current-fps.txt | while read -r fp; do
            jq --arg fp "$fp" '.runs[0].results[] | 
                select(.partialFingerprints.primaryLocationLineHash == $fp) | 
                "\(.ruleId): \(.message.text) at \(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine)"' "$current"
        done
    fi
}

# Usage
case "${1:-}" in
    baseline)
        create_baseline "${2:-.}"
        ;;
    compare)
        compare_to_baseline "${2:-.}"
        ;;
    *)
        echo "Usage: $0 {baseline|compare} [directory]"
        exit 1
        ;;
esac
```

## Advanced Usage

### Custom Rule Filtering

Filter results by rule category:

```bash
# Security issues only
jq '.runs[0].results[] | 
    select(.ruleId | startswith("SEC"))' output.sarif

# Quality issues
jq '.runs[0].results[] | 
    select(.ruleId | startswith("QUAL"))' output.sarif
```

### Suppression List

Create a suppression file to ignore known false positives:

```bash
# suppressions.json
{
  "suppressions": [
    {
      "fingerprint": "abc123...",
      "reason": "False positive - validated manually",
      "date": "2025-11-11"
    }
  ]
}
```

Filter script:

```bash
#!/usr/bin/env bash
# Apply suppressions to SARIF output

sarif_file="$1"
suppressions="suppressions.json"

# Get suppressed fingerprints
suppressed_fps=$(jq -r '.suppressions[].fingerprint' "$suppressions")

# Filter results
jq --argjson suppressed "$(jq -r '[.suppressions[].fingerprint]' "$suppressions")" '
  .runs[0].results = [
    .runs[0].results[] | 
    select(.partialFingerprints.primaryLocationLineHash as $fp | 
           $suppressed | index($fp) | not)
  ]
' "$sarif_file"
```

### Integration with Code Review Tools

Convert SARIF to GitHub review comments:

```bash
#!/usr/bin/env bash
# Convert SARIF to GitHub review comment format

sarif_file="$1"

jq -r '.runs[0].results[] | 
  {
    path: .locations[0].physicalLocation.artifactLocation.uri,
    position: .locations[0].physicalLocation.region.startLine,
    body: "**\(.ruleId)** (\(.level)): \(.message.text)"
  } | @json' "$sarif_file"
```

## Best Practices

1. **Run scans early**: Integrate into pre-commit hooks
2. **Track baselines**: Monitor security posture over time
3. **Automate in CI/CD**: Catch issues before merge
4. **Review regularly**: Schedule periodic security reviews
5. **Suppress wisely**: Document all suppressions with reasons
6. **Keep rules updated**: Regularly update rule versions
7. **Validate outputs**: Always validate SARIF files
8. **Archive reports**: Keep historical scans for audit trails

## Troubleshooting

### No findings reported

- Check file patterns match your scripts
- Verify scripts are readable
- Review rule definitions for applicability

### Too many false positives

- Review rule logic in scanner
- Use suppression lists for known safe cases
- Consider adjusting rule sensitivity

### Performance issues

- Scan smaller directories
- Use file patterns to limit scope
- Consider parallel scanning for large codebases

## Resources

- [SARIF Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)
- [SARIF ABI Contract Documentation](./SARIF_ABI_CONTRACT.md)
