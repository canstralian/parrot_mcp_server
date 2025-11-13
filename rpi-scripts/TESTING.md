# Testing Guide

## Overview

The Parrot MCP Server has a comprehensive testing infrastructure covering:
- **Unit Tests**: Individual function and script validation
- **Integration Tests**: End-to-end workflow and component interaction testing
- **Security Tests**: Input validation, IPC security, and vulnerability checks
- **Manual Tests**: Interactive CLI and system administration workflows

## Test Infrastructure

### Framework
- **Bats** (Bash Automated Testing System) - Primary test framework
- **ShellCheck** - Static analysis and linting
- **shfmt** - Code formatting validation

### Test Organization

```
tests/
├── fixtures/
│   └── test_helpers.bash          # Common test utilities and assertions
├── config_validation.bats         # Configuration and validation tests
├── health_check.bats              # Health check script tests
├── hello.bats                     # Basic script tests
├── mcp_protocol.bats              # MCP protocol compliance tests
├── integration_server_lifecycle.bats    # Server lifecycle integration tests
├── integration_script_execution.bats    # Script execution integration tests
└── integration_security.bats      # Security-focused integration tests
```

## Installation

### Install Bats
```sh
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core

# Manual installation
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Install Linting Tools
```sh
# Ubuntu/Debian
sudo apt-get install shellcheck

# macOS
brew install shellcheck shfmt
```

## Running Tests

### Quick Start

Run the comprehensive integration test suite:
```sh
./run_integration_tests.sh
```

### Test Categories

Run specific test categories:
```sh
# Server lifecycle tests (start, stop, restart, message handling)
./run_integration_tests.sh --category lifecycle

# Script execution and CLI tests
./run_integration_tests.sh --category scripts

# Security and input validation tests
./run_integration_tests.sh --category security

# Run only existing tests (pre-integration suite)
./run_integration_tests.sh --category existing

# Run all tests (default)
./run_integration_tests.sh --category all
```

### Test Options

```sh
# Verbose output
./run_integration_tests.sh --verbose

# CI mode (auto-install dependencies, strict mode)
./run_integration_tests.sh --ci

# Help
./run_integration_tests.sh --help
```

### Individual Test Files

Run specific test files:
```sh
# Run single test file
bats tests/integration_server_lifecycle.bats

# Run with verbose output
bats -t tests/integration_security.bats

# Run all tests in directory
bats tests/
```

## Linting and Formatting

### ShellCheck (Static Analysis)
```sh
# Check all scripts
shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh

# Check specific script
shellcheck start_mcp_server.sh

# Disable specific warnings (use sparingly)
# shellcheck disable=SC2034
```

### shfmt (Code Formatting)
```sh
# Check formatting
shfmt -d cli.sh scripts/*.sh

# Auto-format files
shfmt -w cli.sh scripts/*.sh

# Format with specific options
shfmt -i 2 -ci -w scripts/*.sh
```

## Manual Testing

### Interactive CLI Testing
```sh
# Run CLI menu
./cli.sh

# Test specific scripts
./cli.sh hello
./cli.sh health_check
./cli.sh check_disk
```

### Server Lifecycle Testing
```sh
# Start server
./start_mcp_server.sh

# Check logs
tail -f ./logs/parrot.log

# Stop server
./stop_mcp_server.sh
```

### MCP Protocol Testing
```sh
# Run protocol compliance tests
./test_mcp_local.sh
```

### Cron Integration Testing
```sh
# Setup cron jobs
./cli.sh setup_cron

# Verify cron entries
crontab -l

# Test daily workflow
./scripts/daily_workflow.sh
```

## Writing Tests

### Test Structure

```bash
#!/usr/bin/env bats

# Setup runs before each test
setup() {
    ORIG_DIR="$(pwd)"
    cd "$(dirname "$BATS_TEST_FILENAME")/.."
    TEST_DIR="$(mktemp -d)"
}

# Teardown runs after each test
teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

@test "descriptive test name" {
    # Arrange
    echo '{"test": "data"}' > "$TEST_DIR/test.json"
    
    # Act
    run ./cli.sh hello
    
    # Assert
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hello"* ]]
}
```

### Using Test Helpers

```bash
#!/usr/bin/env bats

load fixtures/test_helpers

@test "using helper functions" {
    # Create MCP message
    create_mcp_message "test" "ping" "/tmp/test_msg.json"
    
    # Validate JSON
    validate_json "/tmp/test_msg.json"
    [ "$?" -eq 0 ]
    
    # Assert file exists
    assert_file_exists "/tmp/test_msg.json" "Message file should exist"
    
    # Clean up
    cleanup_test_artifacts "test_"
}
```

### Best Practices

1. **Use descriptive test names** - Explain what is being tested
2. **Arrange-Act-Assert pattern** - Structure tests clearly
3. **Clean up resources** - Use teardown to remove test artifacts
4. **Test one thing** - Each test should verify a single behavior
5. **Make tests independent** - Tests should not depend on each other
6. **Handle async operations** - Use proper wait/timeout patterns
7. **Mock external dependencies** - Avoid network calls, external tools

### Common Assertions

```bash
# Exit status
[ "$status" -eq 0 ]
[ "$status" -ne 0 ]

# String matching
[[ "$output" == *"expected"* ]]
[[ "$output" =~ pattern ]]

# File checks
[ -f "file.txt" ]
[ -x "script.sh" ]
[ -d "directory" ]

# Numeric comparisons
[ "$count" -gt 0 ]
[ "$size" -lt 1000 ]
```

## Integration Test Coverage

### Server Lifecycle Tests (integration_server_lifecycle.bats)
- ✓ Server start/stop/restart cycles
- ✓ MCP protocol message handling (valid, malformed, missing)
- ✓ Logging and error handling
- ✓ Concurrent operations and race conditions
- ✓ Resource cleanup
- ✓ Edge cases (multiple stops, missing PID file)

### Script Execution Tests (integration_script_execution.bats)
- ✓ CLI execution and error handling
- ✓ Script availability and permissions
- ✓ Bash syntax validation
- ✓ Script headers and documentation
- ✓ Configuration and environment handling
- ✓ Concurrent script execution
- ✓ File system integration

### Security Tests (integration_security.bats)
- ✓ Command injection prevention
- ✓ Input validation (email, path, filename)
- ✓ IPC security (file permissions, /tmp usage)
- ✓ Error message information disclosure
- ✓ Resource exhaustion prevention
- ✓ Shell safety (set -e, variable quoting)
- ✓ No hardcoded credentials
- ✓ File system security

## Coverage Goals

| Component | Target | Status |
|-----------|--------|--------|
| MCP Protocol | 95% | ✓ Met |
| Server Lifecycle | 95% | ✓ Met |
| Script Execution | 85% | ✓ Met |
| Security Validation | 90% | ✓ Met |
| Error Handling | 90% | ✓ Met |
| Integration Paths | 100% | ✓ Met |

## Continuous Integration

### CI Pipeline

The test suite runs automatically on:
- Every pull request
- Commits to main branch
- Nightly comprehensive test runs

### CI Configuration

```yaml
# Example GitHub Actions workflow
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: sudo apt-get install -y bats shellcheck
      - name: Run linting
        run: shellcheck cli.sh scripts/*.sh
      - name: Run tests
        run: cd rpi-scripts && ./run_integration_tests.sh --ci
```

## Troubleshooting

### Common Issues

**Issue: Tests fail with "bats: command not found"**
```sh
# Install bats
sudo apt-get install bats
# Or use manual installation method above
```

**Issue: Server doesn't stop cleanly**
```sh
# Manually stop server
pkill -f start_mcp_server
rm -f ./logs/mcp_server.pid
```

**Issue: Permission denied errors**
```sh
# Ensure scripts are executable
chmod +x cli.sh scripts/*.sh *.sh
```

**Issue: Tests hang or timeout**
```sh
# Check for orphaned processes
ps aux | grep mcp_server
kill <pid>

# Clean up temp files
rm -f /tmp/mcp_*.json
```

### Debug Mode

Enable verbose output:
```sh
# Bats verbose mode
bats -t tests/integration_server_lifecycle.bats

# Enable debug in scripts
export PARROT_DEBUG="true"
./cli.sh hello

# View detailed logs
tail -f ./logs/parrot.log
```

## Test Development Workflow

1. **Write failing test** - Define expected behavior
2. **Implement feature** - Make test pass
3. **Refactor** - Improve code while keeping tests green
4. **Run linting** - Ensure code quality
5. **Run full suite** - Verify no regressions
6. **Document** - Update TESTING.md if needed

## Additional Resources

- [Bats Documentation](https://bats-core.readthedocs.io/)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- [Bash Testing Best Practices](https://github.com/bats-core/bats-core#writing-tests)
- [MCP Server Specification](https://spec.modelcontextprotocol.io/)
