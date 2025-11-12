#!/usr/bin/env bash
# test_sarif_golden.sh - Golden output test for SARIF determinism
# Verifies that SARIF outputs are deterministic and stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "==================================="
echo "SARIF Golden Output Test"
echo "==================================="

# Test fixture
FIXTURE="tests/fixtures/test_script.sh"
OUTPUT1="/tmp/sarif_golden_1.sarif"
OUTPUT2="/tmp/sarif_golden_2.sarif"

# Clean up previous runs
rm -f "$OUTPUT1" "$OUTPUT2"

echo ""
echo "Step 1: Scanning test fixture (run 1)..."
./scripts/sarif_scanner.sh file "$FIXTURE" "$OUTPUT1"

echo ""
echo "Step 2: Scanning test fixture (run 2)..."
./scripts/sarif_scanner.sh file "$FIXTURE" "$OUTPUT2"

echo ""
echo "Step 3: Comparing outputs for determinism..."

# Extract just the results section (excluding timestamps and commit SHAs)
jq 'del(.runs[0].properties.analysisTimestamp, .runs[0].versionControlProvenance[0].revisionId)' "$OUTPUT1" > /tmp/sarif_1_normalized.json
jq 'del(.runs[0].properties.analysisTimestamp, .runs[0].versionControlProvenance[0].revisionId)' "$OUTPUT2" > /tmp/sarif_2_normalized.json

# Compare normalized outputs
if diff -q /tmp/sarif_1_normalized.json /tmp/sarif_2_normalized.json > /dev/null; then
    echo "✓ PASS: Outputs are deterministic (excluding timestamps and commit SHAs)"
else
    echo "✗ FAIL: Outputs differ unexpectedly"
    echo ""
    echo "Differences:"
    diff /tmp/sarif_1_normalized.json /tmp/sarif_2_normalized.json || true
    exit 1
fi

echo ""
echo "Step 4: Verifying partial fingerprints are stable..."

# Extract fingerprints from both runs
jq -r '.runs[0].results[].partialFingerprints.primaryLocationLineHash' "$OUTPUT1" | sort > /tmp/fp1.txt
jq -r '.runs[0].results[].partialFingerprints.primaryLocationLineHash' "$OUTPUT2" | sort > /tmp/fp2.txt

if diff -q /tmp/fp1.txt /tmp/fp2.txt > /dev/null; then
    echo "✓ PASS: Partial fingerprints are stable"
else
    echo "✗ FAIL: Partial fingerprints differ between runs"
    exit 1
fi

echo ""
echo "Step 5: Verifying results are sorted..."

# Check if results are sorted by ruleId
rule_ids=$(jq -r '.runs[0].results[].ruleId' "$OUTPUT1")
sorted_rule_ids=$(echo "$rule_ids" | sort)

if [ "$rule_ids" = "$sorted_rule_ids" ]; then
    echo "✓ PASS: Results are sorted by ruleId"
else
    echo "✗ FAIL: Results are not properly sorted"
    exit 1
fi

echo ""
echo "Step 6: Validating SARIF output..."
if ./scripts/sarif_validator.sh validate "$OUTPUT1" > /dev/null 2>&1; then
    echo "✓ PASS: SARIF output validates successfully"
else
    echo "✗ FAIL: SARIF validation failed"
    exit 1
fi

echo ""
echo "Step 7: Checking expected findings..."

# Expected findings in test_script.sh:
# - 2x SEC001 (hardcoded credentials on lines 6 and 7)
# - 1x SEC002 (insecure random on line 10)
# - 1x QUAL003 (missing error handling on line 13)

finding_count=$(jq '.runs[0].results | length' "$OUTPUT1")
echo "Found $finding_count issue(s)"

sec001_count=$(jq '[.runs[0].results[] | select(.ruleId == "SEC001")] | length' "$OUTPUT1")
sec002_count=$(jq '[.runs[0].results[] | select(.ruleId == "SEC002")] | length' "$OUTPUT1")
qual003_count=$(jq '[.runs[0].results[] | select(.ruleId == "QUAL003")] | length' "$OUTPUT1")

expected_sec001=2
expected_sec002=1
expected_qual003=1

echo "  SEC001: $sec001_count (expected: $expected_sec001)"
echo "  SEC002: $sec002_count (expected: $expected_sec002)"
echo "  QUAL003: $qual003_count (expected: $expected_qual003)"

if [ "$sec001_count" -eq "$expected_sec001" ] && \
   [ "$sec002_count" -eq "$expected_sec002" ] && \
   [ "$qual003_count" -eq "$expected_qual003" ]; then
    echo "✓ PASS: All expected findings detected"
else
    echo "✗ FAIL: Finding counts don't match expectations"
    exit 1
fi

echo ""
echo "==================================="
echo "All golden output tests PASSED"
echo "==================================="

# Clean up
rm -f "$OUTPUT1" "$OUTPUT2" /tmp/sarif_1_normalized.json /tmp/sarif_2_normalized.json /tmp/fp1.txt /tmp/fp2.txt
