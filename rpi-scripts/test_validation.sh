#!/usr/bin/env bash
# Test script for validation functions in common_config.sh

set -euo pipefail

# Load common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common_config.sh
source "${SCRIPT_DIR}/common_config.sh"

echo "=== Testing IP Address Validation ==="
test_ips=("192.168.1.1" "10.0.0.1" "256.1.1.1" "invalid.ip" "127.0.0.1")

for ip in "${test_ips[@]}"; do
    if parrot_validate_ipv4 "$ip"; then
        echo "✓ Valid IPv4: $ip"
    else
        echo "✗ Invalid IPv4: $ip"
    fi
done

echo ""
echo "=== Testing Port Validation ==="
test_ports=(80 443 8080 0 70000 3000 -1 "abc")

for port in "${test_ports[@]}"; do
    if parrot_validate_port "$port" 2>/dev/null; then
        echo "✓ Valid port: $port"
    else
        echo "✗ Invalid port: $port"
    fi
done

echo ""
echo "=== Testing Email Validation ==="
test_emails=("user@example.com" "test@test.co.uk" "invalid.email" "@example.com" "user@")

for email in "${test_emails[@]}"; do
    if parrot_validate_email "$email"; then
        echo "✓ Valid email: $email"
    else
        echo "✗ Invalid email: $email"
    fi
done

echo ""
echo "All validation tests completed!"
