#!/usr/bin/env bash
# run_integration_tests.sh - Comprehensive integration test suite runner
# Usage: ./run_integration_tests.sh [options]
# Options:
#   --verbose    Enable verbose output
#   --coverage   Generate coverage reports (requires kcov or similar)
#   --category   Run specific test category (lifecycle, scripts, security, all)
#   --ci         Run in CI mode (non-interactive, strict)

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
VERBOSE=false
COVERAGE=false
CATEGORY="all"
CI_MODE=false
BATS_INSTALLED=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --coverage|-c)
            COVERAGE=true
            shift
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --verbose,-v     Enable verbose output"
            echo "  --coverage,-c    Generate coverage reports"
            echo "  --category CAT   Run specific category (lifecycle, scripts, security, all)"
            echo "  --ci             Run in CI mode"
            echo "  --help,-h        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Print header
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Parrot MCP Server - Integration Tests${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if bats is installed
if command -v bats >/dev/null 2>&1; then
    BATS_INSTALLED=true
    echo -e "${GREEN}✓${NC} Bats test framework found: $(bats --version)"
else
    echo -e "${RED}✗${NC} Bats test framework not found"
    echo ""
    echo "Bats is required to run these tests. Please install it:"
    echo ""
    echo "  Ubuntu/Debian:  sudo apt-get install bats"
    echo "  macOS:          brew install bats-core"
    echo "  Manual:         git clone https://github.com/bats-core/bats-core.git"
    echo "                  cd bats-core && sudo ./install.sh /usr/local"
    echo ""
    
    if [ "$CI_MODE" = true ]; then
        echo "Attempting to install bats for CI..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y bats || {
                echo "Failed to install bats"
                exit 1
            }
            BATS_INSTALLED=true
        else
            echo "Cannot auto-install bats in this environment"
            exit 1
        fi
    else
        exit 1
    fi
fi

echo ""

# Check for other useful tools
echo "Checking for optional test tools:"
command -v shellcheck >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} ShellCheck available" || echo -e "${YELLOW}○${NC} ShellCheck not available (optional)"
command -v shfmt >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} shfmt available" || echo -e "${YELLOW}○${NC} shfmt not available (optional)"
command -v jq >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} jq available" || echo -e "${YELLOW}○${NC} jq not available (optional)"
echo ""

# Set up test environment
echo "Setting up test environment..."
mkdir -p ./logs
mkdir -p ./logs/tests

# Clean up any previous test runs
echo "Cleaning up previous test artifacts..."
rm -f /tmp/mcp_test_*.json /tmp/mcp_in.json /tmp/mcp_bad.json 2>/dev/null || true

if [ -f "./logs/mcp_server.pid" ]; then
    echo "Stopping any running MCP server..."
    ./stop_mcp_server.sh 2>/dev/null || true
    sleep 1
fi

echo ""

# Function to run test category
run_test_category() {
    local category_name="$1"
    local test_pattern="$2"
    
    echo -e "${BLUE}Running ${category_name} tests...${NC}"
    echo "----------------------------------------"
    
    local test_files=()
    for test_file in tests/${test_pattern}.bats; do
        if [ -f "$test_file" ]; then
            test_files+=("$test_file")
        fi
    done
    
    if [ ${#test_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No test files found matching: tests/${test_pattern}.bats${NC}"
        return 0
    fi
    
    local failed=0
    for test_file in "${test_files[@]}"; do
        echo "Running: $test_file"
        
        if [ "$VERBOSE" = true ]; then
            bats -t "$test_file" || failed=1
        else
            bats "$test_file" || failed=1
        fi
        
        echo ""
    done
    
    return $failed
}

# Track overall results
TOTAL_FAILED=0

# Run tests based on category
case "$CATEGORY" in
    lifecycle)
        run_test_category "Server Lifecycle" "integration_server_lifecycle" || ((TOTAL_FAILED++))
        ;;
    scripts)
        run_test_category "Script Execution" "integration_script_execution" || ((TOTAL_FAILED++))
        ;;
    security)
        run_test_category "Security" "integration_security" || ((TOTAL_FAILED++))
        ;;
    existing)
        echo -e "${BLUE}Running existing test suite...${NC}"
        echo "----------------------------------------"
        for test_file in tests/*.bats; do
            if [[ ! "$test_file" =~ integration_ ]] && [ -f "$test_file" ]; then
                echo "Running: $test_file"
                bats "$test_file" || ((TOTAL_FAILED++))
                echo ""
            fi
        done
        ;;
    all)
        # Run all existing tests first
        echo -e "${BLUE}=== Phase 1: Existing Tests ===${NC}"
        echo ""
        for test_file in tests/*.bats; do
            if [[ ! "$test_file" =~ integration_ ]] && [ -f "$test_file" ]; then
                echo "Running: $test_file"
                bats "$test_file" || ((TOTAL_FAILED++))
                echo ""
            fi
        done
        
        # Run new integration tests
        echo -e "${BLUE}=== Phase 2: Integration Tests ===${NC}"
        echo ""
        run_test_category "Server Lifecycle" "integration_server_lifecycle" || ((TOTAL_FAILED++))
        run_test_category "Script Execution" "integration_script_execution" || ((TOTAL_FAILED++))
        run_test_category "Security" "integration_security" || ((TOTAL_FAILED++))
        ;;
    *)
        echo -e "${RED}Unknown category: $CATEGORY${NC}"
        echo "Valid categories: lifecycle, scripts, security, existing, all"
        exit 1
        ;;
esac

# Clean up after tests
echo -e "${BLUE}Cleaning up...${NC}"
if [ -f "./logs/mcp_server.pid" ]; then
    ./stop_mcp_server.sh 2>/dev/null || true
fi
rm -f /tmp/mcp_test_*.json /tmp/mcp_in.json /tmp/mcp_bad.json 2>/dev/null || true

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Suite Complete${NC}"
echo -e "${BLUE}========================================${NC}"

if [ "$TOTAL_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All test categories passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ $TOTAL_FAILED test category(ies) failed${NC}"
    exit 1
fi
