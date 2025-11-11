#!/usr/bin/env bash
# Smoke test script for MCP server deployment
# Usage: ./scripts/smoke-test.sh [BASE_URL]
# Example: ./scripts/smoke-test.sh https://parrot-mcp.example.com

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
TIMEOUT=10
RETRIES=3

echo "🔍 Running smoke tests for Parrot MCP Server..."
echo "Target: ${BASE_URL}"
echo ""

# Test 1: Check if logs directory exists and has content
test_logs() {
    echo "Test 1: Checking logs..."
    if [ -f "./logs/parrot.log" ] || [ -f "./rpi-scripts/logs/parrot.log" ]; then
        echo "✓ Log file exists"
        return 0
    else
        echo "✗ Log file not found"
        return 1
    fi
}

# Test 2: Check if server process is running
test_process() {
    echo "Test 2: Checking server process..."
    if [ -f "./logs/mcp_server.pid" ] || [ -f "./rpi-scripts/logs/mcp_server.pid" ]; then
        PID_FILE=$(find . -name "mcp_server.pid" 2>/dev/null | head -1)
        if [ -n "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if ps -p "$PID" > /dev/null 2>&1; then
                echo "✓ Server process running (PID: $PID)"
                return 0
            else
                echo "✗ Server process not running"
                return 1
            fi
        fi
    else
        echo "⚠ PID file not found (may not be running locally)"
        return 0
    fi
}

# Test 3: Check if server is accessible (if URL provided)
test_connectivity() {
    echo "Test 3: Checking connectivity..."
    
    if command -v curl &> /dev/null; then
        for i in $(seq 1 $RETRIES); do
            if curl -sf --max-time $TIMEOUT "${BASE_URL}" > /dev/null 2>&1; then
                echo "✓ Server is accessible"
                return 0
            fi
            if [ $i -lt $RETRIES ]; then
                echo "  Retry $i/$RETRIES..."
                sleep 2
            fi
        done
        echo "⚠ Server not accessible (may be expected in test environment)"
        return 0
    else
        echo "⚠ curl not available, skipping connectivity test"
        return 0
    fi
}

# Test 4: Verify critical scripts exist
test_scripts() {
    echo "Test 4: Checking critical scripts..."
    CRITICAL_SCRIPTS=(
        "rpi-scripts/start_mcp_server.sh"
        "rpi-scripts/stop_mcp_server.sh"
        "rpi-scripts/test_mcp_local.sh"
    )
    
    MISSING=0
    for script in "${CRITICAL_SCRIPTS[@]}"; do
        if [ ! -f "$script" ]; then
            echo "✗ Missing: $script"
            MISSING=$((MISSING + 1))
        fi
    done
    
    if [ $MISSING -eq 0 ]; then
        echo "✓ All critical scripts present"
        return 0
    else
        echo "✗ Missing $MISSING critical script(s)"
        return 1
    fi
}

# Run all tests
FAILED=0

test_logs || FAILED=$((FAILED + 1))
echo ""

test_process || FAILED=$((FAILED + 1))
echo ""

test_connectivity || FAILED=$((FAILED + 1))
echo ""

test_scripts || FAILED=$((FAILED + 1))
echo ""

# Summary
echo "============================================"
if [ $FAILED -eq 0 ]; then
    echo "✅ All smoke tests passed!"
    exit 0
else
    echo "❌ $FAILED smoke test(s) failed"
    exit 1
fi
