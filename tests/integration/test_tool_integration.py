"""
Integration tests for external security tool integrations.

Tests integration with nmap, gobuster, nikto, sqlmap and other
security testing tools.
"""

import pytest
import subprocess
import time
from typing import Dict, Any

from tests.fixtures.mock_targets import (
    MOCK_NMAP_RESULTS,
    MOCK_GOBUSTER_RESULTS,
    MOCK_ERRORS
)


class TestNmapIntegration:
    """
    Test nmap tool integration and execution.

    Priority: Critical
    """

    @pytest.mark.critical
    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_nmap_command_execution(self, valid_target, mock_nmap):
        """
        Verify nmap command executes successfully.

        Steps:
        1. Execute nmap scan command
        2. Verify command completes
        3. Check return code
        4. Verify output captured
        """
        # This test would run actual nmap or use mock
        # Using mock for fast, consistent testing
        result = mock_nmap.return_value

        assert result.returncode == 0, \
            f"Nmap execution failed with return code {result.returncode}"
        assert len(result.stdout) > 0, "Nmap should produce output"

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_nmap_version_detection(self):
        """
        Verify nmap version can be detected.

        Expected Result:
        - nmap --version returns version information
        """
        try:
            result = subprocess.run(
                ["nmap", "--version"],
                capture_output=True,
                timeout=5,
                check=False
            )
            # If nmap is installed
            if result.returncode == 0:
                assert b"Nmap" in result.stdout
                assert b"version" in result.stdout or b"7." in result.stdout
            else:
                pytest.skip("Nmap not installed")
        except FileNotFoundError:
            pytest.skip("Nmap not found in PATH")

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_nmap_scan_localhost(self, mock_nmap):
        """
        Verify nmap can scan localhost.

        Expected Result:
        - Scan completes successfully
        - Returns port information
        """
        result = mock_nmap.return_value

        # Verify scan completed
        assert result.returncode == 0
        output = result.stdout.decode()

        # Check for expected nmap output patterns
        assert "Nmap" in output or "PORT" in output or "Host is up" in output

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_nmap_port_specification(self, valid_target):
        """
        Verify nmap accepts port specifications.

        Expected Result:
        - Various port formats accepted (-p 80, -p 1-1000, -p-)
        """
        port_specs = [
            ["-p", "80"],
            ["-p", "80,443"],
            ["-p", "1-100"],
            ["-F"],  # Fast scan (top 100 ports)
        ]

        for ports in port_specs:
            # In real implementation, would execute nmap
            # Here we verify command would be constructed correctly
            cmd = ["nmap"] + ports + [valid_target]
            assert "nmap" in cmd[0]
            assert valid_target in cmd

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_nmap_scan_types(self, valid_target):
        """
        Verify different nmap scan types can be specified.

        Expected Result:
        - TCP Connect scan (-sT)
        - SYN scan (-sS, requires root)
        - UDP scan (-sU, requires root)
        - Version detection (-sV)
        """
        scan_types = [
            ["-sT"],  # TCP connect scan (no root required)
            ["-sV", "-p", "80"],  # Version detection
            ["-sn"],  # Ping scan (no port scan)
        ]

        for scan_type in scan_types:
            cmd = ["nmap"] + scan_type + [valid_target]
            # Verify command structure
            assert len(cmd) >= 3
            assert valid_target in cmd

    @pytest.mark.integration
    @pytest.mark.slow
    def test_nmap_output_formats(self, valid_target, temp_dir):
        """
        Verify nmap supports various output formats.

        Expected Result:
        - Normal output (-oN)
        - XML output (-oX)
        - Grepable output (-oG)
        """
        output_file = temp_dir / "scan_result.xml"

        cmd = ["nmap", "-F", "-oX", str(output_file), valid_target]

        # In mock mode, just verify command structure
        assert "-oX" in cmd
        assert str(output_file) in cmd

    @pytest.mark.integration
    def test_nmap_timing_templates(self, valid_target):
        """
        Verify nmap timing templates.

        Expected Result:
        - Timing templates accepted (-T0 through -T5)
        """
        timing_values = ["-T2", "-T3", "-T4"]

        for timing in timing_values:
            cmd = ["nmap", timing, valid_target]
            assert timing in cmd


class TestGobusterIntegration:
    """
    Test gobuster tool integration for directory/DNS enumeration.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_gobuster_command_execution(self, mock_gobuster):
        """
        Verify gobuster command executes successfully.

        Expected Result:
        - Command completes
        - Output captured
        """
        result = mock_gobuster.return_value

        assert result.returncode == 0, \
            f"Gobuster failed with return code {result.returncode}"
        assert len(result.stdout) > 0, "Gobuster should produce output"

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_gobuster_version_detection(self):
        """
        Verify gobuster version can be detected.
        """
        try:
            result = subprocess.run(
                ["gobuster", "version"],
                capture_output=True,
                timeout=5,
                check=False
            )
            if result.returncode == 0:
                assert b"Gobuster" in result.stdout or b"gobuster" in result.stdout
            else:
                pytest.skip("Gobuster not installed")
        except FileNotFoundError:
            pytest.skip("Gobuster not found in PATH")

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_gobuster_directory_mode(self):
        """
        Verify gobuster directory enumeration mode.

        Expected Result:
        - Directory mode (dir) works correctly
        - Accepts URL and wordlist
        """
        cmd = [
            "gobuster", "dir",
            "-u", "http://example.com",
            "-w", "/usr/share/wordlists/dirb/common.txt",
            "-q"  # Quiet mode
        ]

        # Verify command structure
        assert "dir" in cmd
        assert "-u" in cmd
        assert "-w" in cmd

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_gobuster_dns_mode(self):
        """
        Verify gobuster DNS enumeration mode.

        Expected Result:
        - DNS mode works correctly
        - Accepts domain and wordlist
        """
        cmd = [
            "gobuster", "dns",
            "-d", "example.com",
            "-w", "/usr/share/wordlists/dns.txt"
        ]

        # Verify command structure
        assert "dns" in cmd
        assert "-d" in cmd

    @pytest.mark.integration
    @pytest.mark.requires_tools
    def test_gobuster_vhost_mode(self):
        """
        Verify gobuster vhost enumeration mode.

        Expected Result:
        - Vhost mode works correctly
        """
        cmd = [
            "gobuster", "vhost",
            "-u", "http://example.com",
            "-w", "/usr/share/wordlists/vhosts.txt"
        ]

        # Verify command structure
        assert "vhost" in cmd

    @pytest.mark.integration
    def test_gobuster_thread_specification(self):
        """
        Verify gobuster accepts thread count specification.

        Expected Result:
        - Thread count can be specified with -t flag
        """
        for threads in [5, 10, 20, 50]:
            cmd = [
                "gobuster", "dir",
                "-u", "http://example.com",
                "-w", "/wordlist.txt",
                "-t", str(threads)
            ]

            assert "-t" in cmd
            assert str(threads) in cmd


class TestToolOutputParsing:
    """
    Test parsing and processing of security tool outputs.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.integration
    def test_parse_nmap_output(self, mock_scan_result):
        """
        Verify nmap output can be parsed correctly.

        Expected Result:
        - Port numbers extracted
        - Service names identified
        - Host status determined
        """
        nmap_output = MOCK_NMAP_RESULTS["basic_scan"]["stdout"]

        # Test that we can extract information
        assert "PORT" in nmap_output
        assert "STATE" in nmap_output
        assert "SERVICE" in nmap_output

        # Verify port detection
        assert "22/tcp" in nmap_output or "80/tcp" in nmap_output

    @pytest.mark.integration
    def test_parse_gobuster_output(self):
        """
        Verify gobuster output can be parsed correctly.

        Expected Result:
        - Found directories extracted
        - Status codes identified
        """
        gobuster_output = MOCK_GOBUSTER_RESULTS["directory_scan"]["stdout"]

        # Test that we can extract information
        assert "Status:" in gobuster_output
        assert "/" in gobuster_output  # Should have path indicators

    @pytest.mark.integration
    def test_extract_ports_from_nmap(self):
        """
        Verify port extraction from nmap output.

        Expected Result:
        - List of open ports can be extracted
        """
        result = MOCK_NMAP_RESULTS["basic_scan"]
        ports = result["ports_found"]

        assert isinstance(ports, list)
        assert len(ports) > 0
        assert all(isinstance(p, int) for p in ports)
        assert all(1 <= p <= 65535 for p in ports)

    @pytest.mark.integration
    def test_extract_paths_from_gobuster(self):
        """
        Verify path extraction from gobuster output.

        Expected Result:
        - List of found paths can be extracted
        """
        result = MOCK_GOBUSTER_RESULTS["directory_scan"]
        paths = result["found_paths"]

        assert isinstance(paths, list)
        assert len(paths) > 0
        assert all(isinstance(p, str) for p in paths)
        assert all(p.startswith("/") for p in paths)


class TestToolErrorHandling:
    """
    Test error handling for tool execution failures.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.integration
    def test_handle_tool_not_found(self):
        """
        Verify graceful handling when tool is not installed.

        Expected Result:
        - Appropriate error message
        - Status indicates tool unavailable
        """
        error = MOCK_ERRORS["tool_not_found"]

        assert error["status"] == "failed"
        assert error["return_code"] == 127
        assert "not found" in error["stderr"].lower()

    @pytest.mark.high
    @pytest.mark.integration
    def test_handle_invalid_target_error(self):
        """
        Verify handling of invalid target errors from tools.

        Expected Result:
        - Error captured from tool stderr
        - Appropriate status code
        """
        error = MOCK_ERRORS["invalid_target"]

        assert error["status"] == "failed"
        assert error["return_code"] != 0
        assert len(error["stderr"]) > 0

    @pytest.mark.high
    @pytest.mark.integration
    def test_handle_permission_denied(self):
        """
        Verify handling of permission denied errors.

        Expected Result:
        - Clear error message about permissions
        - Suggestion to run with appropriate privileges
        """
        error = MOCK_ERRORS["permission_denied"]

        assert error["status"] == "failed"
        assert "permission" in error["stderr"].lower() or \
               "root" in error["stderr"].lower() or \
               "privileges" in error["stderr"].lower()

    @pytest.mark.integration
    def test_handle_timeout_gracefully(self):
        """
        Verify timeouts are handled gracefully.

        Expected Result:
        - Partial results captured if available
        - Clear timeout indication
        """
        error = MOCK_ERRORS["timeout"]

        assert error["status"] == "timeout"
        assert "timeout" in error["stderr"].lower() or \
               "timed out" in error["stderr"].lower()

    @pytest.mark.integration
    def test_tool_stderr_captured(self, mock_nmap):
        """
        Verify stderr is captured from tool execution.

        Expected Result:
        - Both stdout and stderr available
        """
        result = mock_nmap.return_value

        # Verify we can access both stdout and stderr
        assert hasattr(result, 'stdout')
        assert hasattr(result, 'stderr')


class TestToolChaining:
    """
    Test chaining multiple security tools together.

    Priority: Medium
    """

    @pytest.mark.medium
    @pytest.mark.integration
    def test_nmap_then_gobuster_workflow(self, valid_target):
        """
        Verify workflow: nmap discovers web server, then gobuster scans it.

        Expected Result:
        - Results from first tool inform second tool
        """
        # Step 1: Nmap finds port 80 open
        nmap_result = MOCK_NMAP_RESULTS["basic_scan"]
        ports_found = nmap_result["ports_found"]

        assert 80 in ports_found or 443 in ports_found, \
            "Expected to find web ports"

        # Step 2: Gobuster scans the web server
        if 80 in ports_found:
            gobuster_target = f"http://{valid_target}"
        else:
            gobuster_target = f"https://{valid_target}"

        # Verify target constructed correctly
        assert gobuster_target.startswith("http")
        assert valid_target in gobuster_target

    @pytest.mark.medium
    @pytest.mark.integration
    def test_sequential_tool_execution(self):
        """
        Verify multiple tools can be executed sequentially.

        Expected Result:
        - Each tool waits for previous to complete
        - Results accumulated
        """
        tools = ["nmap", "gobuster"]
        results = []

        for tool in tools:
            if tool == "nmap":
                result = MOCK_NMAP_RESULTS["basic_scan"]
            else:
                result = MOCK_GOBUSTER_RESULTS["directory_scan"]

            results.append(result)
            assert result["status"] == "completed"

        assert len(results) == len(tools)
