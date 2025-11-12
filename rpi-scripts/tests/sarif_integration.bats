#!/usr/bin/env bats
# sarif_integration.bats - Integration tests for SARIF ABI Contract implementation
# Tests rule registry, generator, validator, and scanner

setup() {
    # Create temporary directory for test outputs
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    
    # Set paths
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
    export SCRIPT_DIR
}

teardown() {
    # Clean up temporary directory
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "sarif_rules_registry: lists all rules" {
    run bash "${SCRIPT_DIR}/scripts/sarif_rules_registry.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SEC001" ]]
    [[ "$output" =~ "QUAL001" ]]
    [[ "$output" =~ "PERF001" ]]
}

@test "sarif_rules_registry: gets rule version" {
    run bash "${SCRIPT_DIR}/scripts/sarif_rules_registry.sh" version SEC001
    [ "$status" -eq 0 ]
    [[ "$output" =~ "1.0.0" ]]
}

@test "sarif_rules_registry: gets rule description" {
    run bash "${SCRIPT_DIR}/scripts/sarif_rules_registry.sh" description SEC001
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hardcoded credentials" ]]
}

@test "sarif_rules_registry: validates rule ID format" {
    run bash "${SCRIPT_DIR}/scripts/sarif_rules_registry.sh" validate SEC001
    [ "$status" -eq 0 ]
    
    run bash "${SCRIPT_DIR}/scripts/sarif_rules_registry.sh" validate INVALID
    [ "$status" -ne 0 ]
}

@test "sarif_generator: generates valid SARIF header" {
    local output="${TEST_DIR}/test_sarif.json"
    run bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" generate "$output"
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    
    # Check JSON is valid
    run jq empty "$output"
    [ "$status" -eq 0 ]
}

@test "sarif_generator: includes required SARIF fields" {
    local output="${TEST_DIR}/test_sarif.json"
    bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" generate "$output"
    
    # Check version
    run jq -r '.version' "$output"
    [ "$output" = "2.1.0" ]
    
    # Check tool name
    run jq -r '.runs[0].tool.driver.name' "$output"
    [[ "$output" =~ "Parrot MCP Server" ]]
    
    # Check provenance
    run jq -e '.runs[0].versionControlProvenance' "$output"
    [ "$status" -eq 0 ]
}

@test "sarif_generator: generates deterministic fingerprints" {
    run bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" fingerprint SEC001 "test.sh" 10 1
    [ "$status" -eq 0 ]
    local fp1="$output"
    
    run bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" fingerprint SEC001 "test.sh" 10 1
    [ "$status" -eq 0 ]
    local fp2="$output"
    
    # Same input should produce same fingerprint
    [ "$fp1" = "$fp2" ]
}

@test "sarif_validator: validates correct SARIF syntax" {
    local output="${TEST_DIR}/test_sarif.json"
    bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" generate "$output"
    
    run bash "${SCRIPT_DIR}/scripts/sarif_validator.sh" syntax "$output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
}

@test "sarif_validator: detects invalid JSON" {
    local output="${TEST_DIR}/invalid.json"
    echo '{"invalid": json}' > "$output"
    
    run bash "${SCRIPT_DIR}/scripts/sarif_validator.sh" syntax "$output"
    [ "$status" -ne 0 ]
}

@test "sarif_validator: comprehensive validation passes" {
    local output="${TEST_DIR}/test_sarif.json"
    bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" generate "$output"
    
    run bash "${SCRIPT_DIR}/scripts/sarif_validator.sh" validate "$output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Validation PASSED" ]]
}

@test "sarif_scanner: scans single file" {
    local test_file="${TEST_DIR}/test_script.sh"
    local output="${TEST_DIR}/scan_output.sarif"
    
    # Create test file with a known issue
    cat > "$test_file" <<'EOF'
#!/usr/bin/env bash
password="hardcoded123"
echo "Test"
EOF
    
    run bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" file "$test_file" "$output"
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    
    # Check that it found the hardcoded credential
    run jq -r '.runs[0].results[0].ruleId' "$output"
    [ "$output" = "SEC001" ]
}

@test "sarif_scanner: generates deterministic output" {
    local test_file="${TEST_DIR}/test_script.sh"
    local output1="${TEST_DIR}/scan1.sarif"
    local output2="${TEST_DIR}/scan2.sarif"
    
    cat > "$test_file" <<'EOF'
#!/usr/bin/env bash
password="test123"
EOF
    
    bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" file "$test_file" "$output1"
    bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" file "$test_file" "$output2"
    
    # Check that fingerprints are identical
    fp1=$(jq -r '.runs[0].results[0].partialFingerprints.primaryLocationLineHash' "$output1")
    fp2=$(jq -r '.runs[0].results[0].partialFingerprints.primaryLocationLineHash' "$output2")
    
    [ "$fp1" = "$fp2" ]
}

@test "sarif_scanner: output validates successfully" {
    local test_file="${TEST_DIR}/test_script.sh"
    local output="${TEST_DIR}/scan_output.sarif"
    
    cat > "$test_file" <<'EOF'
#!/usr/bin/env bash
echo "Test"
EOF
    
    bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" file "$test_file" "$output"
    
    run bash "${SCRIPT_DIR}/scripts/sarif_validator.sh" validate "$output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Validation PASSED" ]]
}

@test "sarif_scanner: detects multiple rule violations" {
    local test_file="${TEST_DIR}/test_script.sh"
    local output="${TEST_DIR}/scan_output.sarif"
    
    cat > "$test_file" <<'EOF'
#!/usr/bin/env bash
password="secret123"
random_num=$RANDOM
eval "dangerous command"
EOF
    
    bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" file "$test_file" "$output"
    
    # Should have multiple findings
    result_count=$(jq '.runs[0].results | length' "$output")
    [ "$result_count" -ge 2 ]
}

@test "sarif_scanner: results are sorted deterministically" {
    local test_file="${TEST_DIR}/test_script.sh"
    local output="${TEST_DIR}/scan_output.sarif"
    
    cat > "$test_file" <<'EOF'
#!/usr/bin/env bash
password="secret"
token="abc123"
random=$RANDOM
EOF
    
    bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" file "$test_file" "$output"
    
    # Extract rule IDs in order
    rule_ids=$(jq -r '.runs[0].results[].ruleId' "$output")
    sorted_rule_ids=$(echo "$rule_ids" | sort)
    
    # Rule IDs should already be sorted
    [ "$rule_ids" = "$sorted_rule_ids" ]
}

@test "integration: full scan and validate workflow" {
    local scan_dir="${TEST_DIR}/scan_target"
    local output="${TEST_DIR}/full_scan.sarif"
    
    mkdir -p "$scan_dir"
    
    # Create multiple test files
    cat > "${scan_dir}/file1.sh" <<'EOF'
#!/usr/bin/env bash
api_key="hardcoded_key"
EOF
    
    cat > "${scan_dir}/file2.sh" <<'EOF'
#!/usr/bin/env bash
value=$RANDOM
EOF
    
    # Scan directory
    run bash "${SCRIPT_DIR}/scripts/sarif_scanner.sh" scan "$scan_dir" "$output"
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    
    # Validate output
    run bash "${SCRIPT_DIR}/scripts/sarif_validator.sh" validate "$output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Validation PASSED" ]]
}

@test "integration: provenance metadata is complete" {
    local output="${TEST_DIR}/test_sarif.json"
    bash "${SCRIPT_DIR}/scripts/sarif_generator.sh" generate "$output"
    
    # Check for version control details
    run jq -e '.runs[0].versionControlProvenance[0].repositoryUri' "$output"
    [ "$status" -eq 0 ]
    
    run jq -e '.runs[0].versionControlProvenance[0].revisionId' "$output"
    [ "$status" -eq 0 ]
    
    # Check for properties
    run jq -e '.runs[0].properties.analysisTimestamp' "$output"
    [ "$status" -eq 0 ]
    
    run jq -e '.runs[0].properties.chainOfCustody' "$output"
    [ "$status" -eq 0 ]
}
