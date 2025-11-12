#!/usr/bin/env bats
# Tests for common_config.sh utility functions

setup() {
    # Load common configuration
    source ./rpi-scripts/common_config.sh
}

# Email validation tests
@test "parrot_validate_email: valid email" {
    run parrot_validate_email "user@example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: valid email with subdomain" {
    run parrot_validate_email "user@mail.example.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: valid email with numbers" {
    run parrot_validate_email "user123@example123.com"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_email: invalid email - no @" {
    run parrot_validate_email "userexample.com"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_email: invalid email - no domain" {
    run parrot_validate_email "user@"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_email: invalid email - spaces" {
    run parrot_validate_email "user @example.com"
    [ "$status" -ne 0 ]
}

# Number validation tests
@test "parrot_validate_number: valid positive number" {
    run parrot_validate_number "123"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_number: valid zero" {
    run parrot_validate_number "0"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_number: invalid negative number" {
    run parrot_validate_number "-123"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_number: invalid decimal" {
    run parrot_validate_number "12.34"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_number: invalid text" {
    run parrot_validate_number "abc"
    [ "$status" -ne 0 ]
}

# Percentage validation tests
@test "parrot_validate_percentage: valid percentage 0" {
    run parrot_validate_percentage "0"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_percentage: valid percentage 50" {
    run parrot_validate_percentage "50"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_percentage: valid percentage 100" {
    run parrot_validate_percentage "100"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_percentage: invalid percentage -1" {
    run parrot_validate_percentage "-1"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_percentage: invalid percentage 101" {
    run parrot_validate_percentage "101"
    [ "$status" -ne 0 ]
}

# Path validation tests
@test "parrot_validate_path: valid relative path" {
    run parrot_validate_path "logs/parrot.log"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_path: valid absolute path in /tmp" {
    run parrot_validate_path "/tmp/test.json"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_path: valid absolute path in /var" {
    run parrot_validate_path "/var/log/test.log"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_path: invalid path with null byte" {
    run parrot_validate_path "test$(printf '\0')file"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_path: invalid path traversal ../" {
    run parrot_validate_path "../etc/passwd"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_path: invalid path traversal /../" {
    run parrot_validate_path "/tmp/../etc/passwd"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_path: invalid absolute path in /etc" {
    run parrot_validate_path "/etc/passwd"
    [ "$status" -ne 0 ]
}

# Script name validation tests
@test "parrot_validate_script_name: valid name with letters" {
    run parrot_validate_script_name "hello"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: valid name with underscore" {
    run parrot_validate_script_name "health_check"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: valid name with dash" {
    run parrot_validate_script_name "daily-workflow"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: valid name with numbers" {
    run parrot_validate_script_name "script123"
    [ "$status" -eq 0 ]
}

@test "parrot_validate_script_name: invalid name starting with number" {
    run parrot_validate_script_name "123script"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_script_name: invalid name with spaces" {
    run parrot_validate_script_name "hello world"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_script_name: invalid name with dots" {
    run parrot_validate_script_name "hello.sh"
    [ "$status" -ne 0 ]
}

@test "parrot_validate_script_name: invalid name with slashes" {
    run parrot_validate_script_name "scripts/hello"
    [ "$status" -ne 0 ]
}

# Sanitize input tests
@test "parrot_sanitize_input: removes null bytes" {
    result=$(parrot_sanitize_input "test$(printf '\0')file")
    [[ "$result" == "testfile" ]]
}

@test "parrot_sanitize_input: removes carriage returns" {
    result=$(parrot_sanitize_input "test$(printf '\r')file")
    [[ "$result" == "testfile" ]]
}

@test "parrot_sanitize_input: preserves newlines" {
    result=$(parrot_sanitize_input "test$(printf '\n')file")
    [[ "$result" == "test"$'\n'"file" ]]
}

@test "parrot_sanitize_input: preserves tabs" {
    result=$(parrot_sanitize_input "test$(printf '\t')file")
    [[ "$result" == "test"$'\t'"file" ]]
}

@test "parrot_sanitize_input: preserves normal text" {
    result=$(parrot_sanitize_input "Hello World 123!")
    [[ "$result" == "Hello World 123!" ]]
}

# Command exists tests
@test "parrot_command_exists: bash exists" {
    run parrot_command_exists "bash"
    [ "$status" -eq 0 ]
}

@test "parrot_command_exists: nonexistent command" {
    run parrot_command_exists "definitely_not_a_real_command_12345"
    [ "$status" -ne 0 ]
}

# Root check tests
@test "parrot_is_root: check if running as root" {
    # This test will pass/fail depending on test environment
    # Just ensure it returns a valid exit code
    run parrot_is_root
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
