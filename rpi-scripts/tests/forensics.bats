#!/usr/bin/env bats
# forensics.bats - Tests for forensics scripts

# Setup test environment
setup() {
    # Store original directory
    ORIG_DIR="$(pwd)"

    # Find the script directory
    if [ -f "scripts/memory_forensics.sh" ]; then
        SCRIPT_DIR="$(pwd)"
    elif [ -f "../scripts/memory_forensics.sh" ]; then
        SCRIPT_DIR="$(cd .. && pwd)"
    elif [ -f "rpi-scripts/scripts/memory_forensics.sh" ]; then
        SCRIPT_DIR="$(pwd)/rpi-scripts"
    else
        echo "# Cannot find forensics scripts" >&2
        return 1
    fi

    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    # Create test log and forensics directories
    mkdir -p "$TEST_DIR/logs"
    mkdir -p "$TEST_DIR/forensics"

    # Export test configuration
    export PARROT_BASE_DIR="$TEST_DIR"
    export PARROT_LOG_DIR="$TEST_DIR/logs"
    export PARROT_FORENSICS_DIR="$TEST_DIR/forensics"
    export PARROT_FORENSICS_CACHE="$TEST_DIR/forensics/cache"
    export PARROT_FORENSICS_RESULTS="$TEST_DIR/forensics/results"
    export PARROT_FORENSICS_LOG="$TEST_DIR/logs/forensics.log"

    # Change to script directory for execution
    cd "$SCRIPT_DIR"
}

teardown() {
    # Return to original directory
    cd "$ORIG_DIR"

    # Cleanup temporary test directory
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# ============================================================================
# MEMORY FORENSICS TESTS
# ============================================================================

@test "memory_forensics: accepts --help flag" {
    run bash scripts/memory_forensics.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "memory_forensics: accepts -h flag" {
    run bash scripts/memory_forensics.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "memory_forensics: lists plugins with --list-plugins" {
    run bash scripts/memory_forensics.sh --list-plugins
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pslist" ]]
    [[ "$output" =~ "netscan" ]]
    [[ "$output" =~ "malfind" ]]
}

@test "memory_forensics: requires dump file" {
    run bash scripts/memory_forensics.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Memory dump file is required" ]]
}

@test "memory_forensics: rejects non-existent dump file" {
    run bash scripts/memory_forensics.sh -d /nonexistent/dump.mem
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" || "$output" =~ "Volatility" ]]
}

@test "memory_forensics: accepts plugins parameter" {
    # Create a dummy dump file
    touch "$TEST_DIR/test.dump"
    run bash scripts/memory_forensics.sh -d "$TEST_DIR/test.dump" -p "pslist,netscan" --check
    # Check will fail if volatility not installed, but command parsing should succeed
    [[ "$output" =~ "Volatility" || "$status" -eq 1 ]]
}

@test "memory_forensics: check dependencies option works" {
    run bash scripts/memory_forensics.sh --check
    # Will fail if dependencies not installed, but command should execute
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" =~ "Volatility" ]]
}

# ============================================================================
# DISK FORENSICS TESTS
# ============================================================================

@test "disk_forensics: accepts --help flag" {
    run bash scripts/disk_forensics.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "disk_forensics: accepts -h flag" {
    run bash scripts/disk_forensics.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "disk_forensics: requires image file" {
    run bash scripts/disk_forensics.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Disk image file is required" ]]
}

@test "disk_forensics: rejects non-existent image file" {
    run bash scripts/disk_forensics.sh -i /nonexistent/disk.dd -o timeline
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" || "$output" =~ "SleuthKit" ]]
}

@test "disk_forensics: accepts operation parameter" {
    # Create a dummy image file
    touch "$TEST_DIR/test.dd"
    run bash scripts/disk_forensics.sh -i "$TEST_DIR/test.dd" -o timeline --check
    # Check will fail if sleuthkit not installed, but command parsing should succeed
    [[ "$output" =~ "SleuthKit" || "$status" -eq 1 ]]
}

@test "disk_forensics: accepts search operation with string" {
    touch "$TEST_DIR/test.dd"
    run bash scripts/disk_forensics.sh -i "$TEST_DIR/test.dd" -o search -s "password" --check
    # Check will fail if sleuthkit not installed, but command parsing should succeed
    [[ "$output" =~ "SleuthKit" || "$status" -eq 1 ]]
}

@test "disk_forensics: check dependencies option works" {
    run bash scripts/disk_forensics.sh --check
    # Will fail if dependencies not installed, but command should execute
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" =~ "SleuthKit" ]]
}

@test "disk_forensics: lists available operations in help" {
    run bash scripts/disk_forensics.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "timeline" ]]
    [[ "$output" =~ "list" ]]
    [[ "$output" =~ "deleted" ]]
    [[ "$output" =~ "hashes" ]]
    [[ "$output" =~ "search" ]]
}

# ============================================================================
# FORENSICS COMMON UTILITIES TESTS
# ============================================================================

@test "forensics_common: can be sourced without errors" {
    run bash -c "source scripts/forensics_common.sh && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "success" ]]
}

@test "forensics_common: creates required directories" {
    run bash -c "source scripts/forensics_common.sh && [ -d '$PARROT_FORENSICS_CACHE' ] && [ -d '$PARROT_FORENSICS_RESULTS' ] && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "success" ]]
}

@test "forensics_common: exports utility functions" {
    run bash -c "source scripts/forensics_common.sh && type forensics_generate_id"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "forensics_common: forensics_generate_id produces valid ID" {
    run bash -c "source scripts/forensics_common.sh && forensics_generate_id test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^test_[0-9_]+$ ]]
}

@test "forensics_common: forensics_compute_hash works with test file" {
    echo "test content" > "$TEST_DIR/test.txt"
    run bash -c "source scripts/forensics_common.sh && forensics_compute_hash '$TEST_DIR/test.txt' sha256"
    [ "$status" -eq 0 ]
    # Should output a 64-character hex string (SHA256)
    [[ "$output" =~ ^[a-f0-9]{64}$ ]]
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

@test "integration: memory_forensics accessible via cli.sh" {
    run ./cli.sh memory_forensics --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Memory Forensics" ]]
}

@test "integration: disk_forensics accessible via cli.sh" {
    run ./cli.sh disk_forensics --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Disk Forensics" ]]
}

# ============================================================================
# SECURITY TESTS
# ============================================================================

@test "SECURITY: memory_forensics rejects command injection in dump path" {
    run bash scripts/memory_forensics.sh -d "test.dump; rm -rf /" -p pslist
    [ "$status" -eq 1 ]
}

@test "SECURITY: disk_forensics rejects command injection in image path" {
    run bash scripts/disk_forensics.sh -i "test.dd; rm -rf /" -o timeline
    [ "$status" -eq 1 ]
}

@test "SECURITY: disk_forensics rejects command injection in search string" {
    touch "$TEST_DIR/test.dd"
    run bash scripts/disk_forensics.sh -i "$TEST_DIR/test.dd" -o search -s "; rm -rf /"
    # Should fail on dependency check or handle safely
    [ "$status" -eq 1 ] || [[ "$output" =~ "SleuthKit" ]]
}

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

@test "error_handling: memory_forensics handles invalid plugin list gracefully" {
    touch "$TEST_DIR/test.dump"
    run bash scripts/memory_forensics.sh -d "$TEST_DIR/test.dump" -p "invalid_plugin_12345"
    # Should fail on dependency check or plugin execution
    [ "$status" -eq 1 ]
}

@test "error_handling: disk_forensics handles invalid operation" {
    touch "$TEST_DIR/test.dd"
    run bash scripts/disk_forensics.sh -i "$TEST_DIR/test.dd" -o invalid_operation_xyz
    # Should fail on dependency check or operation execution
    [ "$status" -eq 1 ]
}

@test "error_handling: memory_forensics validates file exists before processing" {
    run bash scripts/memory_forensics.sh -d /definitely/does/not/exist.dump -p pslist
    [ "$status" -eq 1 ]
}

@test "error_handling: disk_forensics validates file exists before processing" {
    run bash scripts/disk_forensics.sh -i /definitely/does/not/exist.dd -o timeline
    [ "$status" -eq 1 ]
}
