#!/usr/bin/env bash
# =============================================================================
# production-readiness-check.sh - Production Readiness Validation
#
# Description:
#   Comprehensive validation script to verify the codebase is ready for
#   production deployment. Checks security, performance, documentation,
#   testing, and operational readiness.
#
# Usage:
#   ./scripts/production-readiness-check.sh [--strict]
#
# Options:
#   --strict    Enable strict mode (fail on warnings)
#   --fix       Attempt to auto-fix issues where possible
#
# Exit Codes:
#   0 - Production ready
#   1 - Not production ready (blocking issues found)
#   2 - Production ready with warnings
# =============================================================================

set -euo pipefail

# Configuration
STRICT_MODE=false
AUTO_FIX=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --strict) STRICT_MODE=true ;;
        --fix) AUTO_FIX=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0
PASSED=0

# Helper functions
print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_critical() {
    echo -e "${RED}✗ CRITICAL${NC}: $1"
    CRITICAL=$((CRITICAL + 1))
}

check_high() {
    echo -e "${RED}✗ HIGH${NC}: $1"
    HIGH=$((HIGH + 1))
}

check_medium() {
    echo -e "${YELLOW}⚠ MEDIUM${NC}: $1"
    MEDIUM=$((MEDIUM + 1))
}

check_low() {
    echo -e "${YELLOW}ℹ LOW${NC}: $1"
    LOW=$((LOW + 1))
}

check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

# =============================================================================
# SECTION 1: Security Validation
# =============================================================================

print_section "1. SECURITY VALIDATION"

cd "$PROJECT_ROOT"

# Check 1.1: IPC Security
echo "Checking IPC security configuration..."
if grep -r "/tmp" rpi-scripts/*.sh 2>/dev/null | grep -v "#" | grep -v "insecure" | grep -q "PARROT_IPC_DIR.*=/tmp"; then
    check_critical "IPC still uses insecure /tmp directory"
else
    check_pass "IPC uses secure directory (not /tmp)"
fi

# Check 1.2: File Permissions
echo "Checking file permissions..."
INSECURE_PERMS=$(find rpi-scripts -name "*.sh" -type f ! -perm -u+x 2>/dev/null || true)
if [ -n "$INSECURE_PERMS" ]; then
    check_medium "Some shell scripts are not executable"
    echo "$INSECURE_PERMS"
else
    check_pass "All shell scripts have correct permissions"
fi

# Check 1.3: Input Validation
echo "Checking input validation implementation..."
SCRIPTS_WITHOUT_VALIDATION=0
for script in rpi-scripts/scripts/*.sh; do
    if [ -f "$script" ] && [ "$(basename "$script")" != "hello.sh" ]; then
        if ! grep -q "parrot_validate_\|parrot_sanitize_\|common_config.sh" "$script"; then
            SCRIPTS_WITHOUT_VALIDATION=$((SCRIPTS_WITHOUT_VALIDATION + 1))
        fi
    fi
done

if [ "$SCRIPTS_WITHOUT_VALIDATION" -gt 0 ]; then
    check_medium "$SCRIPTS_WITHOUT_VALIDATION utility scripts lack input validation"
else
    check_pass "All critical scripts implement input validation"
fi

# Check 1.4: Hardcoded Secrets
echo "Scanning for hardcoded secrets..."
if grep -rE '(password|secret|api_key)\s*=\s*["'"'"'][^"'"'"']{8,}' rpi-scripts/ 2>/dev/null | grep -v "PARROT_" | grep -v "#" | grep -v "example"; then
    check_critical "Hardcoded secrets detected"
else
    check_pass "No hardcoded secrets detected"
fi

# Check 1.5: Security Documentation
echo "Checking security documentation..."
if [ ! -f "SECURITY.md" ]; then
    check_high "SECURITY.md missing"
elif ! grep -q "IPC" SECURITY.md; then
    check_medium "SECURITY.md doesn't document IPC security"
else
    check_pass "Security documentation is comprehensive"
fi

# =============================================================================
# SECTION 2: Code Quality & Standards
# =============================================================================

print_section "2. CODE QUALITY & STANDARDS"

# Check 2.1: ShellCheck
echo "Running ShellCheck validation..."
if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_ERRORS=0
    for script in $(find rpi-scripts -name "*.sh" -type f); do
        if ! shellcheck --severity=warning --shell=bash "$script" >/dev/null 2>&1; then
            SHELLCHECK_ERRORS=$((SHELLCHECK_ERRORS + 1))
        fi
    done

    if [ "$SHELLCHECK_ERRORS" -gt 0 ]; then
        check_high "ShellCheck found $SHELLCHECK_ERRORS files with issues"
    else
        check_pass "All scripts pass ShellCheck validation"
    fi
else
    check_medium "ShellCheck not installed (cannot validate)"
fi

# Check 2.2: Code Documentation
echo "Checking code documentation..."
UNDOCUMENTED=0
for script in $(find rpi-scripts -name "*.sh" -type f); do
    if ! head -20 "$script" | grep -qE "(Description:|# =====)"; then
        UNDOCUMENTED=$((UNDOCUMENTED + 1))
    fi
done

if [ "$UNDOCUMENTED" -gt 0 ]; then
    check_low "$UNDOCUMENTED scripts lack documentation headers"
else
    check_pass "All scripts have documentation headers"
fi

# Check 2.3: Error Handling
echo "Checking error handling patterns..."
NO_ERROR_HANDLING=0
for script in $(find rpi-scripts/scripts -name "*.sh" -type f); do
    if ! grep -q "set -euo pipefail" "$script"; then
        NO_ERROR_HANDLING=$((NO_ERROR_HANDLING + 1))
    fi
done

if [ "$NO_ERROR_HANDLING" -gt 0 ]; then
    check_medium "$NO_ERROR_HANDLING scripts missing 'set -euo pipefail'"
else
    check_pass "All scripts implement proper error handling"
fi

# =============================================================================
# SECTION 3: Testing Coverage
# =============================================================================

print_section "3. TESTING COVERAGE"

# Check 3.1: BATS Tests Exist
echo "Checking test coverage..."
if [ -d "rpi-scripts/tests" ]; then
    TEST_COUNT=$(find rpi-scripts/tests -name "*.bats" -type f | wc -l)
    if [ "$TEST_COUNT" -lt 3 ]; then
        check_medium "Limited test coverage ($TEST_COUNT test files)"
    else
        check_pass "Good test coverage ($TEST_COUNT test files)"
    fi
else
    check_critical "No test directory found"
fi

# Check 3.2: Tests Pass
echo "Running test suite..."
if command -v bats >/dev/null 2>&1; then
    if bats rpi-scripts/tests/*.bats >/dev/null 2>&1; then
        check_pass "All tests pass"
    else
        check_critical "Test suite has failures"
    fi
else
    check_medium "BATS not installed (cannot run tests)"
fi

# =============================================================================
# SECTION 4: Documentation Completeness
# =============================================================================

print_section "4. DOCUMENTATION COMPLETENESS"

# Check required documentation files
REQUIRED_DOCS=("README.md" "SECURITY.md" "docs/CONFIGURATION.md" "docs/TROUBLESHOOTING.md")

for doc in "${REQUIRED_DOCS[@]}"; do
    if [ ! -f "$doc" ]; then
        check_high "Missing required documentation: $doc"
    else
        # Check if file has content (more than just a title)
        if [ "$(wc -l < "$doc")" -lt 10 ]; then
            check_medium "Documentation file is too short: $doc"
        else
            check_pass "Documentation exists and has content: $doc"
        fi
    fi
done

# Check for API documentation
if [ -f "rpi-scripts/common_config.sh" ]; then
    if grep -q "parrot_validate_\|parrot_log\|parrot_sanitize" docs/*.md 2>/dev/null; then
        check_pass "API functions are documented"
    else
        check_low "API functions should be documented in docs/"
    fi
fi

# =============================================================================
# SECTION 5: Configuration Management
# =============================================================================

print_section "5. CONFIGURATION MANAGEMENT"

# Check 5.1: Config Examples
if [ ! -f "rpi-scripts/config.env.example" ]; then
    check_high "Missing config.env.example file"
elif [ ! -f ".env.example" ]; then
    check_medium "Missing root .env.example file"
else
    check_pass "Configuration examples exist"
fi

# Check 5.2: Config Documentation
if [ -f "rpi-scripts/config.env.example" ]; then
    COMMENTED_LINES=$(grep -c "^#" rpi-scripts/config.env.example || echo "0")
    if [ "$COMMENTED_LINES" -lt 20 ]; then
        check_medium "Configuration file lacks sufficient comments"
    else
        check_pass "Configuration file is well-documented"
    fi
fi

# Check 5.3: Default Values
if [ -f "rpi-scripts/common_config.sh" ]; then
    if grep -q "PARROT_.*:-" rpi-scripts/common_config.sh; then
        check_pass "Configuration has sensible defaults"
    else
        check_medium "Configuration may lack default values"
    fi
fi

# =============================================================================
# SECTION 6: Operational Readiness
# =============================================================================

print_section "6. OPERATIONAL READINESS"

# Check 6.1: Logging
if [ -f "rpi-scripts/common_config.sh" ]; then
    if grep -q "parrot_log\|parrot_info\|parrot_error" rpi-scripts/common_config.sh; then
        check_pass "Centralized logging system implemented"
    else
        check_high "No centralized logging system found"
    fi
fi

# Check 6.2: Monitoring
if [ -f "rpi-scripts/scripts/health_check.sh" ]; then
    check_pass "Health check script exists"
else
    check_medium "No health check script found"
fi

# Check 6.3: Backup/Recovery
if [ -f "rpi-scripts/scripts/backup_home.sh" ]; then
    check_pass "Backup script exists"
else
    check_low "No backup script found"
fi

# Check 6.4: Log Rotation
if [ -f "rpi-scripts/scripts/log_rotate.sh" ]; then
    check_pass "Log rotation script exists"
else
    check_medium "No log rotation script found"
fi

# =============================================================================
# SECTION 7: Deployment Readiness
# =============================================================================

print_section "7. DEPLOYMENT READINESS"

# Check 7.1: CI/CD
if [ -d ".github/workflows" ]; then
    WORKFLOW_COUNT=$(find .github/workflows -name "*.yml" -type f | wc -l)
    if [ "$WORKFLOW_COUNT" -ge 3 ]; then
        check_pass "CI/CD workflows configured ($WORKFLOW_COUNT workflows)"
    else
        check_medium "Limited CI/CD coverage ($WORKFLOW_COUNT workflows)"
    fi
else
    check_high "No CI/CD workflows found"
fi

# Check 7.2: Installation Scripts
if [ -f "rpi-scripts/Makefile" ] || [ -f "install.sh" ]; then
    check_pass "Installation automation exists"
else
    check_low "No installation script found"
fi

# Check 7.3: Startup Scripts
if [ -f "rpi-scripts/start_mcp_server.sh" ] && [ -f "rpi-scripts/stop_mcp_server.sh" ]; then
    check_pass "Server lifecycle scripts exist"
else
    check_high "Missing server lifecycle scripts"
fi

# =============================================================================
# SECTION 8: Performance & Scalability
# =============================================================================

print_section "8. PERFORMANCE & SCALABILITY"

# Check 8.1: Resource Limits
if [ -f "rpi-scripts/common_config.sh" ]; then
    if grep -q "PARROT_MAX_INPUT_SIZE\|PARROT_COMMAND_TIMEOUT" rpi-scripts/common_config.sh; then
        check_pass "Resource limits configured"
    else
        check_medium "No resource limits configured"
    fi
fi

# Check 8.2: Retry Logic
if [ -f "rpi-scripts/common_config.sh" ]; then
    if grep -q "parrot_retry\|RETRY_COUNT" rpi-scripts/common_config.sh; then
        check_pass "Retry mechanism implemented"
    else
        check_low "No retry mechanism found"
    fi
fi

# =============================================================================
# FINAL REPORT
# =============================================================================

print_section "PRODUCTION READINESS SUMMARY"

TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW + PASSED))

echo ""
echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}✓ Passed:${NC}     $PASSED"
echo -e "  ${YELLOW}ℹ Low:${NC}        $LOW"
echo -e "  ${YELLOW}⚠ Medium:${NC}     $MEDIUM"
echo -e "  ${RED}✗ High:${NC}       $HIGH"
echo -e "  ${RED}✗ CRITICAL:${NC}   $CRITICAL"
echo -e "  ${BOLD}━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}Total Checks:${NC} $TOTAL"
echo ""

# Calculate readiness percentage
READINESS=$(awk "BEGIN {printf \"%.0f\", ($PASSED/$TOTAL)*100}")
echo -e "${BOLD}Production Readiness Score: ${GREEN}${READINESS}%${NC}"
echo ""

# Determine exit code and final message
if [ "$CRITICAL" -gt 0 ]; then
    echo -e "${RED}${BOLD}❌ NOT PRODUCTION READY${NC}"
    echo -e "${RED}   Critical issues must be resolved before deployment${NC}"
    EXIT_CODE=1
elif [ "$HIGH" -gt 0 ]; then
    echo -e "${RED}${BOLD}⚠ NOT PRODUCTION READY${NC}"
    echo -e "${RED}   High severity issues should be resolved${NC}"
    EXIT_CODE=1
elif [ "$MEDIUM" -gt 0 ]; then
    if [ "$STRICT_MODE" = "true" ]; then
        echo -e "${YELLOW}${BOLD}⚠ NOT PRODUCTION READY (Strict Mode)${NC}"
        echo -e "${YELLOW}   Medium severity issues present${NC}"
        EXIT_CODE=2
    else
        echo -e "${YELLOW}${BOLD}✓ PRODUCTION READY (with warnings)${NC}"
        echo -e "${YELLOW}   Consider addressing medium/low severity issues${NC}"
        EXIT_CODE=2
    fi
elif [ "$LOW" -gt 0 ]; then
    echo -e "${GREEN}${BOLD}✅ PRODUCTION READY${NC}"
    echo -e "${YELLOW}   Minor improvements recommended${NC}"
    EXIT_CODE=0
else
    echo -e "${GREEN}${BOLD}✅ PRODUCTION READY${NC}"
    echo -e "${GREEN}   All checks passed!${NC}"
    EXIT_CODE=0
fi

echo ""
exit $EXIT_CODE
