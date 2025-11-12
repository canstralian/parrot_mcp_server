"""
Pytest configuration and shared fixtures for MCP Kali Server integration tests.

This module provides common fixtures, test configuration, and utilities
used across all test suites.
"""

import os
import json
import tempfile
import subprocess
from pathlib import Path
from typing import Generator, Dict, Any
from unittest.mock import Mock, patch

import pytest
import requests
from faker import Faker

# Initialize Faker for test data generation
fake = Faker()


# ============================================================================
# Configuration Fixtures
# ============================================================================

@pytest.fixture(scope="session")
def test_config() -> Dict[str, Any]:
    """
    Provide test configuration for the MCP server.

    Returns:
        Dictionary containing test configuration
    """
    return {
        "base_url": os.getenv("MCP_BASE_URL", "http://localhost:5000"),
        "timeout": int(os.getenv("MCP_TIMEOUT", "180")),
        "log_dir": os.getenv("MCP_LOG_DIR", "./logs"),
        "test_target": os.getenv("TEST_TARGET", "scanme.nmap.org"),
        "max_retries": 3,
        "retry_delay": 2,
    }


@pytest.fixture(scope="session")
def project_root() -> Path:
    """Return the project root directory."""
    return Path(__file__).parent.parent


# ============================================================================
# Server Management Fixtures
# ============================================================================

@pytest.fixture(scope="session")
def mcp_server(test_config: Dict[str, Any], project_root: Path):
    """
    Start and stop the MCP server for testing.

    This fixture starts the server before tests run and ensures
    it's properly stopped after all tests complete.
    """
    # Start server script
    start_script = project_root / "rpi-scripts" / "start_mcp_server.sh"
    stop_script = project_root / "rpi-scripts" / "stop_mcp_server.sh"

    if not start_script.exists():
        pytest.skip("MCP server start script not found")

    # Start the server
    proc = subprocess.Popen(
        [str(start_script)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=str(project_root / "rpi-scripts")
    )

    # Wait for server to be ready
    import time
    time.sleep(3)

    yield proc

    # Cleanup: stop the server
    if stop_script.exists():
        subprocess.run([str(stop_script)], cwd=str(project_root / "rpi-scripts"))

    proc.terminate()
    proc.wait(timeout=5)


@pytest.fixture
def api_client(test_config: Dict[str, Any]) -> requests.Session:
    """
    Provide a configured requests session for API testing.

    Returns:
        Configured requests.Session instance
    """
    session = requests.Session()
    session.headers.update({
        "Content-Type": "application/json",
        "User-Agent": "MCP-Test-Client/1.0"
    })
    return session


# ============================================================================
# Test Data Fixtures
# ============================================================================

@pytest.fixture
def valid_target() -> str:
    """Provide a valid test target for security scans."""
    return "scanme.nmap.org"


@pytest.fixture
def invalid_target() -> str:
    """Provide an invalid target for error testing."""
    return "999.999.999.999"


@pytest.fixture
def malicious_target() -> str:
    """Provide a target that attempts command injection."""
    return "127.0.0.1; rm -rf /"


@pytest.fixture
def mock_scan_result() -> Dict[str, Any]:
    """Provide mock scan results for testing."""
    return {
        "tool": "nmap",
        "target": "scanme.nmap.org",
        "status": "completed",
        "return_code": 0,
        "stdout": """
Starting Nmap 7.94 ( https://nmap.org )
Nmap scan report for scanme.nmap.org (45.33.32.156)
Host is up (0.087s latency).
Not shown: 996 closed ports
PORT      STATE SERVICE
22/tcp    open  ssh
80/tcp    open  http
9929/tcp  open  nping-echo
31337/tcp open  Elite

Nmap done: 1 IP address (1 host up) scanned in 2.43 seconds
        """.strip(),
        "stderr": "",
        "duration": 2.43,
        "timestamp": "2025-11-12T04:00:00Z"
    }


@pytest.fixture
def mock_gobuster_result() -> Dict[str, Any]:
    """Provide mock gobuster results for testing."""
    return {
        "tool": "gobuster",
        "target": "http://scanme.nmap.org",
        "status": "completed",
        "return_code": 0,
        "stdout": """
===============================================================
Gobuster v3.6
===============================================================
[+] Url:                     http://scanme.nmap.org
[+] Method:                  GET
[+] Threads:                 10
[+] Wordlist:                /usr/share/wordlists/dirb/common.txt
[+] Status codes:            200,204,301,302,307,401,403
===============================================================
/index.html           (Status: 200) [Size: 7734]
/images               (Status: 301) [Size: 312]
===============================================================
        """.strip(),
        "stderr": "",
        "found_paths": ["/index.html", "/images"],
        "timestamp": "2025-11-12T04:00:00Z"
    }


# ============================================================================
# Temporary Resources Fixtures
# ============================================================================

@pytest.fixture
def temp_dir() -> Generator[Path, None, None]:
    """Provide a temporary directory for test files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def temp_log_file(temp_dir: Path) -> Path:
    """Provide a temporary log file for testing."""
    log_file = temp_dir / "test.log"
    log_file.touch()
    return log_file


@pytest.fixture
def mock_credentials() -> Dict[str, str]:
    """Provide mock credentials for authentication testing."""
    return {
        "api_key": "test_api_key_12345",
        "username": "test_user",
        "password": "test_password_secure123!"
    }


# ============================================================================
# Mock Tool Fixtures
# ============================================================================

@pytest.fixture
def mock_nmap():
    """Mock nmap subprocess execution."""
    with patch('subprocess.run') as mock_run:
        mock_run.return_value = Mock(
            returncode=0,
            stdout="""
Starting Nmap 7.94
Nmap scan report for scanme.nmap.org (45.33.32.156)
Host is up.
PORT   STATE SERVICE
22/tcp open  ssh
80/tcp open  http
Nmap done: 1 IP address scanned
            """.encode(),
            stderr=b""
        )
        yield mock_run


@pytest.fixture
def mock_gobuster():
    """Mock gobuster subprocess execution."""
    with patch('subprocess.run') as mock_run:
        mock_run.return_value = Mock(
            returncode=0,
            stdout=b"/index.html (Status: 200)\n/images (Status: 301)\n",
            stderr=b""
        )
        yield mock_run


# ============================================================================
# Database/State Fixtures
# ============================================================================

@pytest.fixture
def mock_scan_history() -> list:
    """Provide mock scan history data."""
    return [
        {
            "id": 1,
            "tool": "nmap",
            "target": "scanme.nmap.org",
            "timestamp": "2025-11-11T10:00:00Z",
            "status": "completed"
        },
        {
            "id": 2,
            "tool": "gobuster",
            "target": "http://testsite.com",
            "timestamp": "2025-11-11T11:00:00Z",
            "status": "completed"
        },
        {
            "id": 3,
            "tool": "nmap",
            "target": "192.168.1.1",
            "timestamp": "2025-11-11T12:00:00Z",
            "status": "failed"
        }
    ]


# ============================================================================
# Utility Functions
# ============================================================================

def wait_for_server(base_url: str, timeout: int = 30) -> bool:
    """
    Wait for the MCP server to become available.

    Args:
        base_url: Base URL of the server
        timeout: Maximum time to wait in seconds

    Returns:
        True if server is available, False otherwise
    """
    import time
    start_time = time.time()

    while time.time() - start_time < timeout:
        try:
            response = requests.get(f"{base_url}/health", timeout=5)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)

    return False


def assert_valid_json_response(response: requests.Response) -> Dict[str, Any]:
    """
    Assert that the response is valid JSON and return parsed data.

    Args:
        response: HTTP response object

    Returns:
        Parsed JSON data

    Raises:
        AssertionError: If response is not valid JSON
    """
    assert response.headers.get("Content-Type", "").startswith("application/json"), \
        f"Expected JSON content type, got {response.headers.get('Content-Type')}"

    try:
        return response.json()
    except json.JSONDecodeError as e:
        pytest.fail(f"Invalid JSON response: {e}")


# ============================================================================
# Pytest Hooks
# ============================================================================

def pytest_configure(config):
    """Configure pytest with custom settings."""
    # Register custom markers
    config.addinivalue_line(
        "markers", "requires_tools: mark test as requiring external security tools"
    )


def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers automatically."""
    for item in items:
        # Add markers based on test location
        if "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)
        if "security" in item.name.lower():
            item.add_marker(pytest.mark.security)
        if "concurrent" in item.name.lower() or "concurrency" in item.name.lower():
            item.add_marker(pytest.mark.concurrency)
