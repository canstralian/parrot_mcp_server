# MCP Kali Server Integration Testing Guide

## Overview

This document provides comprehensive information about the integration test suite for the Parrot MCP Kali Server. The test suite validates end-to-end functionality, API endpoints, tool integrations, security, concurrency, and error handling.

## Table of Contents

- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Test Categories](#test-categories)
- [Running Tests](#running-tests)
- [Test Configuration](#test-configuration)
- [Coverage Goals](#coverage-goals)
- [CI/CD Integration](#cicd-integration)
- [Writing New Tests](#writing-new-tests)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Prerequisites

- Python 3.8 or higher
- pip package manager
- Security tools (nmap, gobuster, nikto, sqlmap) - optional for full integration tests
- MCP server running (for live integration tests)

### Installation

```bash
# Install test dependencies
pip install -r requirements-test.txt

# Or using make
make install
```

### Run All Tests

```bash
# Using pytest directly
pytest -v

# Using make
make test

# Run only fast tests (exclude slow tests)
make test-fast
```

### Run Specific Test Categories

```bash
# API endpoint tests
make test-api

# Security tests
make test-security

# Tool integration tests
make test-integration

# Concurrency tests
make test-concurrency

# Edge case tests
make test-edge-cases
```

## Test Structure

```
tests/
├── integration/           # Integration test suites
│   ├── test_api_endpoints.py      # API endpoint tests
│   ├── test_tool_integration.py   # Security tool integration
│   ├── test_concurrency.py        # Concurrency and performance
│   ├── test_security.py           # Security vulnerability tests
│   └── test_edge_cases.py         # Edge cases and error handling
├── fixtures/              # Test fixtures and mock data
│   ├── mock_targets.py           # Mock scan targets and results
│   └── test_data.py              # Test data generators
├── conftest.py           # Pytest configuration and shared fixtures
└── __init__.py
```

## Test Categories

### Category 1: API Endpoint Testing (Priority: Critical)

**Location**: `tests/integration/test_api_endpoints.py`

Tests all API endpoints for correct behavior:

- **Health Check Endpoint** (`/health`)
  - Returns 200 status
  - Provides server status
  - Reports tool availability
  - Response time < 1 second

- **Tool Execution Endpoints** (`/api/tools/*`)
  - Nmap integration
  - Gobuster integration
  - Result format validation
  - Parameter handling

- **Error Handling**
  - Invalid inputs rejected (400/422)
  - Missing parameters caught
  - Malformed JSON rejected
  - Appropriate error messages

**Run**: `make test-api` or `pytest -m api`

### Category 2: Tool Integration Testing (Priority: Critical)

**Location**: `tests/integration/test_tool_integration.py`

Tests integration with external security tools:

- **Nmap Integration**
  - Command execution
  - Version detection
  - Port scanning
  - Output parsing

- **Gobuster Integration**
  - Directory enumeration
  - DNS enumeration
  - Vhost discovery
  - Result parsing

- **Tool Output Parsing**
  - Extract ports from nmap
  - Parse gobuster paths
  - Handle errors gracefully

**Run**: `make test-integration` or `pytest -m integration`

### Category 3: Security Testing (Priority: Critical)

**Location**: `tests/integration/test_security.py`

Comprehensive security vulnerability testing:

- **Command Injection Prevention**
  - Semicolon injection (`;`)
  - Pipe injection (`|`)
  - Backtick injection (`` ` ``)
  - Dollar substitution (`$()`)
  - Logical operators (`&&`, `||`)

- **Input Validation**
  - Null byte injection
  - Path traversal attempts
  - SQL injection attempts
  - XSS attempts
  - Buffer overflow prevention

- **Authentication & Authorization**
  - Unauthenticated access blocked
  - Invalid credentials rejected
  - API key validation

- **Security Headers**
  - X-Content-Type-Options
  - X-Frame-Options
  - Strict-Transport-Security

**Run**: `make test-security` or `pytest -m security`

### Category 4: Concurrency Testing (Priority: High)

**Location**: `tests/integration/test_concurrency.py`

Tests concurrent request handling:

- **Concurrent Tool Execution**
  - 10+ simultaneous scans
  - No deadlocks or race conditions
  - Reasonable performance

- **Resource Management**
  - Connection pooling
  - Memory stability
  - File descriptor management

- **Race Conditions**
  - Unique scan ID generation
  - Safe concurrent log writes
  - Shared resource access

- **Load Testing**
  - Sustained load handling
  - Burst traffic tolerance
  - Request queuing

**Run**: `make test-concurrency` or `pytest -m concurrency`

### Category 5: Edge Cases (Priority: Medium)

**Location**: `tests/integration/test_edge_cases.py`

Tests boundary conditions and error scenarios:

- **Timeout Handling**
  - Long-running command timeouts
  - Partial result capture
  - Configurable timeouts

- **Large Output Handling**
  - Large scan outputs
  - Output size limits
  - Streaming support

- **Malformed Inputs**
  - Invalid JSON
  - Missing Content-Type
  - Type mismatches
  - Empty requests

- **Network Edge Cases**
  - Unreachable targets
  - DNS failures
  - IPv6 addresses
  - CIDR notation

**Run**: `make test-edge-cases` or `pytest -m edge_case`

## Running Tests

### Basic Commands

```bash
# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest tests/integration/test_api_endpoints.py

# Run specific test class
pytest tests/integration/test_api_endpoints.py::TestHealthEndpoint

# Run specific test
pytest tests/integration/test_api_endpoints.py::TestHealthEndpoint::test_health_endpoint_returns_200

# Run tests matching keyword
pytest -k "nmap"

# Run tests by marker
pytest -m "critical"
pytest -m "security"
pytest -m "not slow"
```

### Advanced Options

```bash
# Stop on first failure
pytest -x

# Re-run only failed tests
pytest --lf

# Show local variables in tracebacks
pytest -l

# Capture output (show print statements)
pytest -s

# Run tests in parallel (requires pytest-xdist)
pytest -n auto

# Generate HTML report
pytest --html=report.html --self-contained-html
```

### Coverage Reports

```bash
# Run with coverage
pytest --cov=. --cov-report=html --cov-report=term

# View HTML coverage report
make test-coverage-html

# Check coverage threshold
pytest --cov=. --cov-fail-under=85
```

## Test Configuration

### Environment Variables

Configure test behavior with environment variables:

```bash
# MCP server base URL
export MCP_BASE_URL="http://localhost:5000"

# Test timeout (seconds)
export MCP_TIMEOUT="180"

# Test target (for live scans)
export TEST_TARGET="scanme.nmap.org"

# Log directory
export MCP_LOG_DIR="./logs"
```

### Configuration File

Create `.env` file in project root:

```env
MCP_BASE_URL=http://localhost:5000
MCP_TIMEOUT=180
TEST_TARGET=scanme.nmap.org
MCP_LOG_DIR=./logs
```

### Test Markers

Available pytest markers:

- `critical` - Critical priority tests (must pass)
- `high` - High priority tests
- `medium` - Medium priority tests
- `low` - Low priority tests
- `api` - API endpoint tests
- `integration` - Tool integration tests
- `security` - Security tests
- `concurrency` - Concurrency tests
- `edge_case` - Edge case tests
- `slow` - Tests that take > 5 seconds
- `requires_tools` - Tests requiring external tools

## Coverage Goals

| Component | Target Coverage | Critical Coverage |
|-----------|----------------|-------------------|
| Overall | 85% | - |
| API Handlers | 95% | Yes |
| Tool Executors | 95% | Yes |
| Integration Paths | 100% | Yes |
| Error Handlers | 90% | No |

### Current Coverage

Run `make test-coverage` to see current coverage statistics.

## CI/CD Integration

### GitHub Actions

Tests run automatically on:
- Every push to `main`, `develop`, or `claude/*` branches
- Every pull request to `main` or `develop`
- Nightly at 2 AM UTC
- Manual workflow dispatch

### CI Pipeline

1. **Linting** - flake8, black, mypy
2. **Fast Tests** - Quick validation
3. **Critical Tests** - Must-pass tests
4. **Full Test Suite** - All tests with coverage
5. **Coverage Check** - Verify >= 85% coverage
6. **Upload Artifacts** - Coverage reports, test results

### Viewing CI Results

- Check the "Actions" tab in GitHub
- Download artifacts for detailed reports
- Coverage reports posted to pull requests

## Writing New Tests

### Test Template

```python
import pytest
from tests.conftest import assert_valid_json_response

class TestNewFeature:
    """
    Test Case X.Y: Feature Description
    Priority: Critical/High/Medium/Low

    Detailed description of what this test suite covers.
    """

    @pytest.mark.critical  # Or high, medium, low
    @pytest.mark.api  # Or integration, security, etc.
    def test_feature_basic_behavior(self, api_client, test_config):
        """
        Test description.

        Steps:
        1. Step one
        2. Step two
        3. Step three

        Expected Result:
        - Expected outcome
        """
        # Arrange
        payload = {"key": "value"}

        # Act
        response = api_client.post(
            f"{test_config['base_url']}/api/endpoint",
            json=payload,
            timeout=test_config['timeout']
        )

        # Assert
        assert response.status_code == 200
        data = assert_valid_json_response(response)
        assert "expected_field" in data
```

### Best Practices

1. **Use Descriptive Names**
   - Test name should describe what is being tested
   - Use `test_<action>_<expected_result>` pattern

2. **Follow AAA Pattern**
   - Arrange: Set up test data
   - Act: Execute the code being tested
   - Assert: Verify the results

3. **Use Fixtures**
   - Leverage shared fixtures from `conftest.py`
   - Create new fixtures for reusable test data

4. **Add Markers**
   - Mark priority: `@pytest.mark.critical`
   - Mark category: `@pytest.mark.security`
   - Mark slow tests: `@pytest.mark.slow`

5. **Document Tests**
   - Add docstrings explaining purpose
   - Document test steps and expected results
   - Link to related requirements/issues

6. **Handle Errors Gracefully**
   - Use `pytest.skip()` for unavailable features
   - Use `pytest.xfail()` for known failures
   - Provide clear assertion messages

## Troubleshooting

### Common Issues

#### Tests Fail with "Connection Refused"

**Problem**: Cannot connect to MCP server

**Solution**:
```bash
# Check if server is running
curl http://localhost:5000/health

# Start the server
cd rpi-scripts
./start_mcp_server.sh

# Or set correct base URL
export MCP_BASE_URL="http://your-server:5000"
```

#### Tests Timeout

**Problem**: Tests exceed timeout

**Solution**:
```bash
# Increase timeout
export MCP_TIMEOUT="300"

# Or skip slow tests
pytest -m "not slow"
```

#### Security Tools Not Found

**Problem**: Tests skip due to missing tools

**Solution**:
```bash
# Install tools
sudo apt-get install nmap gobuster nikto

# Or run only tests that don't require tools
pytest -m "not requires_tools"
```

#### Coverage Below Threshold

**Problem**: Coverage check fails

**Solution**:
```bash
# See which lines are not covered
pytest --cov=. --cov-report=term-missing

# View HTML report for detailed analysis
make test-coverage-html
```

#### Import Errors

**Problem**: Cannot import test modules

**Solution**:
```bash
# Install test dependencies
pip install -r requirements-test.txt

# Or use make
make install
```

### Debug Mode

Run tests in debug mode:

```bash
# Drop into debugger on failure
pytest --pdb

# Show all output
pytest -s -v

# Very verbose
pytest -vv
```

### Getting Help

1. Check test output carefully - error messages are descriptive
2. Review test documentation in code
3. Check GitHub Issues for similar problems
4. Run `make help` for available commands
5. Check CI logs for detailed error information

## Performance Benchmarks

### Expected Performance

- Health check: < 1 second
- Fast nmap scan: < 30 seconds
- Directory enumeration: < 60 seconds
- Concurrent (10 requests): < 120 seconds

### Benchmarking

```bash
# Run performance tests
make test-benchmark

# Show test durations
pytest --durations=20

# Profile tests
pytest --profile
```

## Contributing

When adding new features:

1. Write tests first (TDD approach)
2. Ensure tests pass locally
3. Check coverage doesn't decrease
4. Update this documentation
5. Submit PR with test results

## Resources

- [pytest Documentation](https://docs.pytest.org/)
- [pytest Best Practices](https://docs.pytest.org/en/stable/goodpractices.html)
- [Testing Best Practices](https://testdriven.io/blog/testing-best-practices/)
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)

## License

This test suite is part of the Parrot MCP Server project and is licensed under the MIT License.
