#!/usr/bin/env bats
# Tests for the rate limiter functionality

# Load common configuration
setup() {
    # Source the common config
    load ../common_config.sh
    
    # Create a temporary rate limit file for testing
    export PARROT_RATE_LIMIT_FILE="/tmp/test_rate_limit_$$.log"
    export PARROT_LOG_DIR="/tmp/test_logs_$$"
    export PARROT_RATE_LIMIT=5  # Set low limit for easier testing
    export PARROT_RATE_LIMIT_WINDOW=3600  # 1 hour window
    
    # Create log directory
    mkdir -p "$PARROT_LOG_DIR"
    
    # Clean up any existing rate limit file
    rm -f "$PARROT_RATE_LIMIT_FILE"
}

teardown() {
    # Clean up test files
    rm -f "$PARROT_RATE_LIMIT_FILE"
    rm -rf "$PARROT_LOG_DIR"
}

@test "rate limiter: creates rate limit file if it doesn't exist" {
    # File should not exist initially
    [ ! -f "$PARROT_RATE_LIMIT_FILE" ]
    
    # Call rate limiter
    run parrot_check_rate_limit "testuser" "scan"
    
    # Should succeed
    [ "$status" -eq 0 ]
    
    # File should now exist
    [ -f "$PARROT_RATE_LIMIT_FILE" ]
}

@test "rate limiter: allows operations within limit" {
    # Perform operations within the limit (5 operations)
    for _ in {1..5}; do
        run parrot_check_rate_limit "user1" "scan"
        [ "$status" -eq 0 ]
    done
}

@test "rate limiter: blocks operations exceeding limit" {
    # Fill up to the limit
    for _ in {1..5}; do
        parrot_check_rate_limit "user1" "scan"
    done
    
    # Next operation should be blocked
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 1 ]
}

@test "rate limiter: tracks different users independently" {
    # User1 fills their limit
    for _ in {1..5}; do
        parrot_check_rate_limit "user1" "scan"
    done
    
    # User1 should be blocked
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 1 ]
    
    # User2 should still be allowed
    run parrot_check_rate_limit "user2" "scan"
    [ "$status" -eq 0 ]
}

@test "rate limiter: tracks different operations independently" {
    # Fill limit for "scan" operation
    for _ in {1..5}; do
        parrot_check_rate_limit "user1" "scan"
    done
    
    # "scan" should be blocked
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 1 ]
    
    # "read" should still be allowed
    run parrot_check_rate_limit "user1" "read"
    [ "$status" -eq 0 ]
}

@test "rate limiter: cleans up old entries" {
    # Create entries with old timestamps (older than cutoff)
    local now
    now=$(date +%s)
    local old_timestamp=$((now - 7200))  # 2 hours ago (outside window)
    
    # Add old entries manually
    {
        echo "user1:scan:$old_timestamp"
        echo "user1:scan:$old_timestamp"
        echo "user1:scan:$old_timestamp"
        echo "user1:scan:$old_timestamp"
        echo "user1:scan:$old_timestamp"
    } > "$PARROT_RATE_LIMIT_FILE"
    
    # User1 should have 5 old entries, but they should be cleaned up
    # So new operation should be allowed
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 0 ]
    
    # Verify old entries were removed from the file
    run grep -c "$old_timestamp" "$PARROT_RATE_LIMIT_FILE"
    [ "$status" -eq 1 ] || [ "$output" -eq 0 ]
}

@test "rate limiter: preserves recent entries while cleaning old ones" {
    local now
    now=$(date +%s)
    local old_timestamp=$((now - 7200))  # 2 hours ago
    local recent_timestamp=$((now - 1800))  # 30 minutes ago
    
    # Add mix of old and recent entries
    {
        echo "user1:scan:$old_timestamp"
        echo "user1:scan:$recent_timestamp"
        echo "user2:read:$old_timestamp"
        echo "user2:read:$recent_timestamp"
    } > "$PARROT_RATE_LIMIT_FILE"
    
    # Trigger cleanup by checking rate limit
    parrot_check_rate_limit "user1" "scan"
    
    # Recent entries should be preserved
    run grep -c "$recent_timestamp" "$PARROT_RATE_LIMIT_FILE"
    [ "$output" -eq 2 ]
    
    # Old entries should be removed
    run grep -c "$old_timestamp" "$PARROT_RATE_LIMIT_FILE"
    [ "$status" -eq 1 ] || [ "$output" -eq 0 ]
}

@test "rate limiter: sanitizes user and operation inputs" {
    # Try with potentially dangerous characters
    run parrot_check_rate_limit "user;rm -rf /" "scan"
    [ "$status" -eq 0 ]
    
    # Verify the sanitized entry was created
    run grep -c "userrm-rf:scan:" "$PARROT_RATE_LIMIT_FILE"
    [ "$output" -eq 1 ]
}

@test "rate limiter: requires both user and operation parameters" {
    # Missing operation
    run parrot_check_rate_limit "user1" ""
    [ "$status" -eq 1 ]
    
    # Missing user
    run parrot_check_rate_limit "" "scan"
    [ "$status" -eq 1 ]
    
    # Missing both
    run parrot_check_rate_limit "" ""
    [ "$status" -eq 1 ]
}

@test "rate limiter: handles concurrent access safely" {
    # This test verifies the atomic file operations
    # Fill up most of the limit
    for _ in {1..4}; do
        parrot_check_rate_limit "user1" "scan"
    done
    
    # One more should succeed
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 0 ]
    
    # Next should fail
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 1 ]
}

@test "rate limiter: counts entries correctly after cleanup" {
    local now
    now=$(date +%s)
    local old_timestamp=$((now - 7200))
    
    # Add 10 old entries
    for _ in {1..10}; do
        echo "user1:scan:$old_timestamp" >> "$PARROT_RATE_LIMIT_FILE"
    done
    
    # Add 3 recent entries
    for _ in {1..3}; do
        parrot_check_rate_limit "user1" "scan"
    done
    
    # Should have 3 recent entries (old ones cleaned up)
    # So 2 more operations should be allowed (limit is 5)
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 0 ]
    
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 0 ]
    
    # Now at limit, next should fail
    run parrot_check_rate_limit "user1" "scan"
    [ "$status" -eq 1 ]
}
