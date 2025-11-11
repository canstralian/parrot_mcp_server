#!/usr/bin/env bash
# sarif_validator.sh - SARIF 2.1.0 schema validation and consistency checking
# Part of SARIF ABI Contract v0.5 Integrity Baseline
# Implements strict validation and environmental issue detection

set -euo pipefail

SARIF_SCHEMA_URL="https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"
SARIF_SCHEMA_CACHE="/tmp/sarif-schema-2.1.0.json"

# Download SARIF schema if not cached
ensure_schema_cached() {
    if [[ ! -f "$SARIF_SCHEMA_CACHE" ]]; then
        if command -v curl &> /dev/null; then
            echo "Downloading SARIF 2.1.0 schema..." >&2
            curl -sSL "$SARIF_SCHEMA_URL" -o "$SARIF_SCHEMA_CACHE" || {
                echo "Warning: Could not download schema, validation will be limited" >&2
                return 1
            }
        elif command -v wget &> /dev/null; then
            echo "Downloading SARIF 2.1.0 schema..." >&2
            wget -q "$SARIF_SCHEMA_URL" -O "$SARIF_SCHEMA_CACHE" || {
                echo "Warning: Could not download schema, validation will be limited" >&2
                return 1
            }
        else
            echo "Warning: Neither curl nor wget available, schema validation disabled" >&2
            return 1
        fi
    fi
    return 0
}

# Validate JSON syntax
validate_json_syntax() {
    local sarif_file="$1"
    
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is required for validation but not found" >&2
        return 1
    fi
    
    if ! jq empty "$sarif_file" 2>/dev/null; then
        echo "FAIL: Invalid JSON syntax in $sarif_file" >&2
        return 1
    fi
    
    echo "PASS: JSON syntax is valid"
    return 0
}

# Validate SARIF version
validate_sarif_version() {
    local sarif_file="$1"
    local version
    
    version=$(jq -r '.version' "$sarif_file" 2>/dev/null)
    
    if [[ "$version" != "2.1.0" ]]; then
        echo "FAIL: Expected SARIF version 2.1.0, found: $version" >&2
        return 1
    fi
    
    echo "PASS: SARIF version is 2.1.0"
    return 0
}

# Validate schema compliance
validate_schema_compliance() {
    local sarif_file="$1"
    
    if ! command -v ajv &> /dev/null; then
        echo "WARN: ajv-cli not available, skipping schema validation" >&2
        echo "  Install with: npm install -g ajv-cli" >&2
        return 0
    fi
    
    if ! ensure_schema_cached; then
        echo "WARN: Schema not available, skipping schema validation" >&2
        return 0
    fi
    
    if ajv validate -s "$SARIF_SCHEMA_CACHE" -d "$sarif_file" 2>&1; then
        echo "PASS: SARIF schema validation passed"
        return 0
    else
        echo "FAIL: SARIF schema validation failed" >&2
        return 1
    fi
}

# Check for required fields
validate_required_fields() {
    local sarif_file="$1"
    local errors=0
    
    echo "Checking required fields..."
    
    # Check version
    if ! jq -e '.version' "$sarif_file" &>/dev/null; then
        echo "  FAIL: Missing 'version' field" >&2
        ((errors++))
    fi
    
    # Check runs array
    if ! jq -e '.runs | type == "array"' "$sarif_file" &>/dev/null; then
        echo "  FAIL: Missing or invalid 'runs' array" >&2
        ((errors++))
    fi
    
    # Check tool information
    if ! jq -e '.runs[0].tool.driver.name' "$sarif_file" &>/dev/null; then
        echo "  FAIL: Missing 'tool.driver.name'" >&2
        ((errors++))
    fi
    
    # Check provenance metadata
    if ! jq -e '.runs[0].versionControlProvenance' "$sarif_file" &>/dev/null; then
        echo "  WARN: Missing 'versionControlProvenance' (recommended)" >&2
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "PASS: All required fields present"
        return 0
    else
        echo "FAIL: $errors required field(s) missing" >&2
        return 1
    fi
}

# Validate deterministic sorting
validate_deterministic_sorting() {
    local sarif_file="$1"
    
    echo "Checking deterministic sorting..."
    
    # Check if results are sorted by ruleId
    local sorted_rule_ids
    local actual_rule_ids
    
    sorted_rule_ids=$(jq -r '.runs[0].results[]?.ruleId' "$sarif_file" 2>/dev/null | sort)
    actual_rule_ids=$(jq -r '.runs[0].results[]?.ruleId' "$sarif_file" 2>/dev/null)
    
    if [[ "$sorted_rule_ids" != "$actual_rule_ids" ]]; then
        echo "  WARN: Results may not be deterministically sorted by ruleId" >&2
    else
        echo "PASS: Results appear to be sorted"
    fi
    
    return 0
}

# Validate partial fingerprints
validate_partial_fingerprints() {
    local sarif_file="$1"
    local missing=0
    
    echo "Checking partial fingerprints..."
    
    local total_results
    total_results=$(jq '.runs[0].results | length' "$sarif_file" 2>/dev/null)
    
    if [[ "$total_results" -gt 0 ]]; then
        local results_with_fingerprints
        results_with_fingerprints=$(jq '[.runs[0].results[] | select(.partialFingerprints)] | length' "$sarif_file" 2>/dev/null)
        
        missing=$((total_results - results_with_fingerprints))
        
        if [[ $missing -gt 0 ]]; then
            echo "  WARN: $missing result(s) missing partial fingerprints" >&2
        else
            echo "PASS: All results have partial fingerprints"
        fi
    else
        echo "INFO: No results to check"
    fi
    
    return 0
}

# Validate URI canonicalization
validate_uri_canonicalization() {
    local sarif_file="$1"
    
    echo "Checking URI canonicalization..."
    
    # Check for absolute paths in URIs
    local absolute_paths
    absolute_paths=$(jq -r '.runs[0].results[]?.locations[]?.physicalLocation?.artifactLocation?.uri' "$sarif_file" 2>/dev/null | grep -c '^/' || true)
    
    if [[ $absolute_paths -gt 0 ]]; then
        echo "  WARN: Found $absolute_paths absolute path(s), should be relative" >&2
    else
        echo "PASS: All URIs appear to be relative"
    fi
    
    # Check for uriBaseId
    local with_base_id
    with_base_id=$(jq '[.runs[0].results[]?.locations[]?.physicalLocation?.artifactLocation? | select(.uriBaseId)] | length' "$sarif_file" 2>/dev/null)
    
    if [[ $with_base_id -eq 0 ]]; then
        echo "  INFO: No uriBaseId found (optional but recommended)" >&2
    else
        echo "PASS: URIs use uriBaseId"
    fi
    
    return 0
}

# Check consistency and environmental issues
check_consistency() {
    local sarif_file="$1"
    
    echo "Checking consistency..."
    
    # Check if all referenced rules are defined
    local rule_ids
    local defined_rules
    
    rule_ids=$(jq -r '.runs[0].results[]?.ruleId' "$sarif_file" 2>/dev/null | sort -u)
    defined_rules=$(jq -r '.runs[0].tool.driver.rules[]?.id' "$sarif_file" 2>/dev/null | sort -u)
    
    if [[ -n "$rule_ids" ]]; then
        while IFS= read -r rule_id; do
            if ! echo "$defined_rules" | grep -q "^${rule_id}$"; then
                echo "  WARN: Rule '$rule_id' used but not defined in driver.rules" >&2
            fi
        done <<< "$rule_ids"
    fi
    
    echo "PASS: Consistency checks completed"
    return 0
}

# Calculate file size and warn if too large
check_file_size() {
    local sarif_file="$1"
    local max_size_mb=10
    
    echo "Checking file size..."
    
    local size_bytes
    size_bytes=$(stat -f%z "$sarif_file" 2>/dev/null || stat -c%s "$sarif_file" 2>/dev/null)
    local size_mb=$((size_bytes / 1024 / 1024))
    
    if [[ $size_mb -gt $max_size_mb ]]; then
        echo "  WARN: SARIF file is ${size_mb}MB, exceeds recommended ${max_size_mb}MB" >&2
        echo "  Consider splitting into multiple files or optimizing output" >&2
    else
        echo "PASS: File size is ${size_mb}MB (within limits)"
    fi
    
    return 0
}

# Comprehensive validation
validate_sarif_comprehensive() {
    local sarif_file="$1"
    local failures=0
    
    echo "==================================="
    echo "SARIF Validation Report"
    echo "==================================="
    echo "File: $sarif_file"
    echo ""
    
    validate_json_syntax "$sarif_file" || ((failures++))
    echo ""
    
    validate_sarif_version "$sarif_file" || ((failures++))
    echo ""
    
    validate_required_fields "$sarif_file" || ((failures++))
    echo ""
    
    validate_deterministic_sorting "$sarif_file" || true
    echo ""
    
    validate_partial_fingerprints "$sarif_file" || true
    echo ""
    
    validate_uri_canonicalization "$sarif_file" || true
    echo ""
    
    check_consistency "$sarif_file" || true
    echo ""
    
    check_file_size "$sarif_file" || true
    echo ""
    
    validate_schema_compliance "$sarif_file" || ((failures++))
    echo ""
    
    echo "==================================="
    if [[ $failures -eq 0 ]]; then
        echo "RESULT: Validation PASSED"
        return 0
    else
        echo "RESULT: Validation FAILED ($failures critical errors)"
        return 1
    fi
}

# Main CLI interface
main() {
    local cmd="${1:-validate}"
    shift || true
    
    case "$cmd" in
        validate)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 validate <sarif_file>" >&2
                exit 1
            fi
            validate_sarif_comprehensive "$1"
            ;;
        syntax)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 syntax <sarif_file>" >&2
                exit 1
            fi
            validate_json_syntax "$1"
            ;;
        schema)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 schema <sarif_file>" >&2
                exit 1
            fi
            ensure_schema_cached
            validate_schema_compliance "$1"
            ;;
        *)
            echo "Usage: $0 {validate|syntax|schema} <sarif_file>" >&2
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
