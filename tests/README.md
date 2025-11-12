# Integration Tests

## Overview

This directory contains comprehensive integration tests for the Parrot MCP Kali Server. The test suite validates API endpoints, security tool integrations, authentication, error handling, and system behavior under various conditions.

## Structure

```
tests/
├── integration/              # Integration test suites
│   ├── test_api_endpoints.py         # API endpoint tests (Critical)
│   ├── test_tool_integration.py      # Tool integration tests (Critical)
│   ├── test_security.py              # Security tests (Critical)
│   ├── test_concurrency.py           # Concurrency tests (High)
│   └── test_edge_cases.py            # Edge case tests (Medium)
├── fixtures/                 # Test data and mocks
│   ├── mock_targets.py              # Mock scan targets and results
│   └── test_data.py                 # Test data generators
├── conftest.py              # Pytest configuration
└── README.md                # This file
```

## Quick Start

```bash
# Install dependencies
pip install -r requirements-test.txt

# Run all tests
pytest -v

# Run specific category
pytest -m api          # API tests
pytest -m security     # Security tests
pytest -m integration  # Tool integration tests
```

## Test Suites

### 1. API Endpoint Tests (`test_api_endpoints.py`)

**Priority**: Critical
**Count**: ~20 tests
**Runtime**: ~2 minutes

Tests all REST API endpoints:
- Health check endpoint validation
- Tool execution endpoints (nmap, gobuster, etc.)
- Error handling and validation
- Response format consistency

**Key Tests**:
- `test_health_endpoint_returns_200` - Health check works
- `test_nmap_scan_with_valid_target` - Nmap integration
- `test_nmap_with_invalid_target` - Error handling

### 2. Tool Integration Tests (`test_tool_integration.py`)

**Priority**: Critical
**Count**: ~25 tests
**Runtime**: ~5 minutes

Tests integration with security tools:
- Nmap command execution and output parsing
- Gobuster directory/DNS enumeration
- Tool error handling
- Output parsing and data extraction

**Key Tests**:
- `test_nmap_command_execution` - Nmap runs successfully
- `test_gobuster_directory_mode` - Gobuster integration
- `test_parse_nmap_output` - Output parsing works

### 3. Security Tests (`test_security.py`)

**Priority**: Critical
**Count**: ~40 tests
**Runtime**: ~3 minutes

Comprehensive security vulnerability testing:
- Command injection prevention (`;`, `|`, `` ` ``, `$()`)
- Input validation (SQL injection, XSS, path traversal)
- Authentication and authorization
- Security headers and HTTPS

**Key Tests**:
- `test_block_semicolon_injection` - Command injection blocked
- `test_path_traversal_prevention` - Path traversal blocked
- `test_unauthenticated_access_blocked` - Auth enforced

### 4. Concurrency Tests (`test_concurrency.py`)

**Priority**: High
**Count**: ~15 tests
**Runtime**: ~10 minutes

Tests concurrent request handling:
- Simultaneous scan execution
- Resource management (connections, memory, file descriptors)
- Race condition detection
- Load and stress testing

**Key Tests**:
- `test_concurrent_nmap_scans` - Handle 10+ concurrent scans
- `test_no_file_descriptor_leak` - FD leak detection
- `test_sustained_load` - System stability under load

### 5. Edge Case Tests (`test_edge_cases.py`)

**Priority**: Medium
**Count**: ~30 tests
**Runtime**: ~8 minutes

Tests boundary conditions and errors:
- Timeout handling
- Large output handling
- Malformed inputs
- Network edge cases (IPv6, DNS failures, unreachable hosts)

**Key Tests**:
- `test_scan_timeout_handled` - Timeouts work correctly
- `test_large_nmap_output_captured` - Large outputs handled
- `test_malformed_json_rejected` - Input validation

## Test Markers

Use markers to run specific test subsets:

```bash
# Priority markers
pytest -m critical    # Must-pass tests
pytest -m high        # High priority
pytest -m medium      # Medium priority

# Category markers
pytest -m api              # API tests
pytest -m integration      # Tool integration tests
pytest -m security         # Security tests
pytest -m concurrency      # Concurrency tests
pytest -m edge_case        # Edge case tests

# Other markers
pytest -m "not slow"       # Skip slow tests (>5s)
pytest -m requires_tools   # Tests needing external tools
```

## Fixtures

### Global Fixtures (from `conftest.py`)

- `test_config` - Test configuration (URLs, timeouts, etc.)
- `api_client` - Configured HTTP client
- `mcp_server` - MCP server instance (session scope)
- `valid_target` - Valid scan target
- `invalid_target` - Invalid target for error testing
- `mock_scan_result` - Mock scan results
- `temp_dir` - Temporary directory

### Mock Data (from `fixtures/`)

- `MOCK_NMAP_RESULTS` - Pre-recorded nmap outputs
- `MOCK_GOBUSTER_RESULTS` - Pre-recorded gobuster outputs
- `MOCK_ERRORS` - Various error scenarios
- `INJECTION_ATTEMPTS` - Command injection test cases

## Configuration

### Environment Variables

```bash
MCP_BASE_URL=http://localhost:5000  # Server URL
MCP_TIMEOUT=180                     # Default timeout
TEST_TARGET=scanme.nmap.org         # Live scan target
MCP_LOG_DIR=./logs                  # Log directory
```

### pytest.ini

Configuration in root `pytest.ini`:
- Test discovery patterns
- Coverage settings
- Marker definitions
- Default options

## Running Tests

### Local Development

```bash
# Fast feedback (skip slow tests)
pytest -m "not slow"

# Run changed tests only
pytest --lf

# Watch mode (requires pytest-watch)
ptw

# Specific test
pytest tests/integration/test_api_endpoints.py::test_health_endpoint_returns_200
```

### Pre-commit Checks

```bash
# Run critical tests
pytest -m critical

# Check coverage
pytest --cov=. --cov-fail-under=85

# Lint and test
make check
```

### CI/CD

Tests run automatically in GitHub Actions:
- On push to main/develop branches
- On pull requests
- Nightly at 2 AM UTC
- Manual trigger

## Writing Tests

### Template

```python
import pytest

class TestNewFeature:
    """Test new feature."""

    @pytest.mark.critical
    @pytest.mark.api
    def test_feature_works(self, api_client, test_config):
        """Test that feature works correctly."""
        # Arrange
        payload = {"key": "value"}

        # Act
        response = api_client.post(
            f"{test_config['base_url']}/api/endpoint",
            json=payload
        )

        # Assert
        assert response.status_code == 200
        data = response.json()
        assert "expected_key" in data
```

### Guidelines

1. **Naming**: `test_<what>_<expected_result>`
2. **Structure**: Arrange → Act → Assert
3. **Markers**: Add priority and category markers
4. **Documentation**: Add docstrings with steps
5. **Independence**: Tests should not depend on each other
6. **Cleanup**: Use fixtures for setup/teardown

## Coverage

### Current Coverage

```bash
# Generate coverage report
pytest --cov=. --cov-report=html

# View in browser
open htmlcov/index.html
```

### Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| Overall | 85% | TBD |
| API handlers | 95% | TBD |
| Tool executors | 95% | TBD |
| Integration paths | 100% | TBD |
| Error handlers | 90% | TBD |

## Performance

### Expected Runtimes

- Fast tests (`-m "not slow"`): ~5 minutes
- All tests: ~30 minutes
- Critical tests only: ~10 minutes

### Optimization

- Use mocks where possible
- Mark slow tests with `@pytest.mark.slow`
- Run in parallel with `-n auto`

## Troubleshooting

### Server Not Running

```bash
# Start server
cd rpi-scripts
./start_mcp_server.sh

# Verify health
curl http://localhost:5000/health
```

### Tests Timing Out

```bash
# Increase timeout
export MCP_TIMEOUT=300

# Or skip slow tests
pytest -m "not slow"
```

### Import Errors

```bash
# Reinstall dependencies
pip install -r requirements-test.txt

# Check Python path
echo $PYTHONPATH
```

### Coverage Issues

```bash
# See uncovered lines
pytest --cov=. --cov-report=term-missing

# Generate detailed HTML report
pytest --cov=. --cov-report=html
```

## Resources

- [Main Testing Documentation](../TESTING.md)
- [pytest Documentation](https://docs.pytest.org/)
- [Security Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)

## Contributing

1. Write tests for new features
2. Ensure tests pass locally
3. Maintain coverage >= 85%
4. Update documentation
5. Submit PR with test results

## Contact

For questions or issues:
- Open a GitHub issue
- Check existing test documentation
- Review CI logs for failures
