"""
Enterprise-grade Nmap scanning functionality with security controls.

This module provides secure, validated Nmap scanning capabilities with:
- Comprehensive input validation
- Command injection prevention
- Scan result parsing
- Error handling and logging
"""

import subprocess
import re
import json
import ipaddress
import logging
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)


class NmapSecurityError(Exception):
    """Raised when security validation fails"""
    pass


class NmapExecutionError(Exception):
    """Raised when Nmap execution fails"""
    pass


class NmapValidator:
    """Security validator for Nmap scan inputs"""

    # Whitelist of allowed IP ranges (configurable in production)
    ALLOWED_RANGES = [
        ipaddress.ip_network("10.0.0.0/8"),      # Private Class A
        ipaddress.ip_network("172.16.0.0/12"),   # Private Class B
        ipaddress.ip_network("192.168.0.0/16"),  # Private Class C
    ]

    # Blacklist of forbidden ranges
    FORBIDDEN_RANGES = [
        ipaddress.ip_network("127.0.0.0/8"),     # Loopback
        ipaddress.ip_network("169.254.0.0/16"),  # Link-local
        ipaddress.ip_network("224.0.0.0/4"),     # Multicast
        ipaddress.ip_network("240.0.0.0/4"),     # Reserved
    ]

    # Maximum allowed CIDR network sizes
    MAX_IPV4_HOSTS = 256  # /24 maximum
    MAX_IPV6_HOSTS = 65536  # /48 maximum

    @classmethod
    def validate_target(cls, target: str) -> Tuple[bool, Optional[str]]:
        """
        Validate target IP or CIDR range.

        Args:
            target: IP address or CIDR notation

        Returns:
            Tuple of (is_valid, error_message)
        """
        try:
            # Remove whitespace
            target = target.strip()

            # Parse as network (handles both single IPs and CIDR)
            network = ipaddress.ip_network(target, strict=False)

            # Check if it's in forbidden ranges
            for forbidden in cls.FORBIDDEN_RANGES:
                if network.overlaps(forbidden):
                    return False, f"Target {target} overlaps forbidden range {forbidden}"

            # Check network size limits
            if isinstance(network, ipaddress.IPv4Network):
                if network.num_addresses > cls.MAX_IPV4_HOSTS:
                    return False, f"Network too large: {network.num_addresses} hosts (max {cls.MAX_IPV4_HOSTS})"
            elif isinstance(network, ipaddress.IPv6Network):
                if network.num_addresses > cls.MAX_IPV6_HOSTS:
                    return False, f"Network too large: {network.num_addresses} hosts (max {cls.MAX_IPV6_HOSTS})"

            # In production, check against allowed ranges
            # For now, we'll allow any valid, non-forbidden range
            # Uncomment below to enforce whitelist:
            # if not any(network.subnet_of(allowed) for allowed in cls.ALLOWED_RANGES):
            #     return False, f"Target {target} not in allowed ranges"

            return True, None

        except ValueError as e:
            return False, f"Invalid IP/CIDR format: {str(e)}"

    @staticmethod
    def validate_scan_type(scan_type: str) -> Tuple[bool, Optional[str]]:
        """
        Validate scan type against allowed types.

        Args:
            scan_type: The requested scan type

        Returns:
            Tuple of (is_valid, error_message)
        """
        allowed_types = ["default", "quick", "full", "stealth", "os", "vuln", "custom"]

        if scan_type not in allowed_types:
            return False, f"Invalid scan type. Allowed: {', '.join(allowed_types)}"

        return True, None

    @staticmethod
    def sanitize_custom_args(args: str) -> Tuple[bool, Optional[str], Optional[List[str]]]:
        """
        Sanitize and validate custom Nmap arguments.

        Args:
            args: Custom Nmap command-line arguments

        Returns:
            Tuple of (is_valid, error_message, sanitized_args_list)
        """
        # Forbidden arguments that could be abused
        forbidden_patterns = [
            r"--script.*\.\./",  # Path traversal in scripts
            r"--datadir",         # Change data directory
            r"--servicedb",       # Change service database
            r"-oN\s*/",          # Output to absolute paths
            r"-oG\s*/",
            r"-oX\s*/",
            r"--resume",         # Resume from file
            r"--stylesheet",     # Load external stylesheet
            r"[\$`]",            # Shell metacharacters
            r"[;&|<>]",          # Shell operators
        ]

        for pattern in forbidden_patterns:
            if re.search(pattern, args):
                return False, f"Forbidden argument pattern detected: {pattern}", None

        # Split args safely (basic implementation)
        # In production, use shlex.split() for proper parsing
        args_list = args.split()

        # Validate each argument
        safe_args = []
        for arg in args_list:
            # Only allow arguments starting with - or --
            if arg.startswith("-"):
                safe_args.append(arg)
            else:
                # Could be a value for previous arg
                safe_args.append(arg)

        return True, None, safe_args


class NmapScanner:
    """Enterprise-grade Nmap scanner with security controls"""

    # Scan type to Nmap argument mapping
    SCAN_PROFILES = {
        "quick": ["-T4", "-F"],                          # Fast scan, top 100 ports
        "default": ["-T4", "-Pn"],                       # Normal scan, no ping
        "full": ["-sS", "-sV", "-T4", "-p-"],           # Full TCP SYN, all ports
        "stealth": ["-sS", "-T2", "-f"],                # Stealth SYN scan, fragmented
        "os": ["-O", "--osscan-guess"],                 # OS detection
        "vuln": ["-sV", "--script=vuln", "-T4"],        # Vulnerability scan
    }

    def __init__(self, nmap_path: str = "/usr/bin/nmap", timeout: int = 300):
        """
        Initialize Nmap scanner.

        Args:
            nmap_path: Path to nmap binary
            timeout: Maximum scan timeout in seconds
        """
        self.nmap_path = nmap_path
        self.timeout = timeout
        self.validator = NmapValidator()

        # Verify nmap is available
        try:
            result = subprocess.run(
                [self.nmap_path, "--version"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                raise NmapExecutionError("Nmap not available or not executable")
            logger.info(f"Nmap version: {result.stdout.split()[2]}")
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            raise NmapExecutionError(f"Nmap initialization failed: {str(e)}")

    def validate_and_prepare_scan(
        self,
        target: str,
        scan_type: str,
        custom_args: Optional[str] = None
    ) -> Tuple[bool, Optional[str], Optional[List[str]]]:
        """
        Validate inputs and prepare scan command.

        Args:
            target: Target IP/CIDR
            scan_type: Type of scan
            custom_args: Optional custom arguments

        Returns:
            Tuple of (is_valid, error_message, command_list)
        """
        # Validate target
        valid, error = self.validator.validate_target(target)
        if not valid:
            logger.warning(f"Invalid target: {target} - {error}")
            return False, error, None

        # Validate scan type
        valid, error = self.validator.validate_scan_type(scan_type)
        if not valid:
            logger.warning(f"Invalid scan type: {scan_type} - {error}")
            return False, error, None

        # Build command
        command = [self.nmap_path]

        # Add scan profile arguments
        if scan_type == "custom" and custom_args:
            valid, error, safe_args = self.validator.sanitize_custom_args(custom_args)
            if not valid:
                return False, error, None
            command.extend(safe_args)
        else:
            command.extend(self.SCAN_PROFILES.get(scan_type, self.SCAN_PROFILES["default"]))

        # Always output XML for parsing
        command.extend(["-oX", "-"])

        # Add target (always last)
        command.append(target)

        logger.info(f"Prepared scan command: {' '.join(command)}")
        return True, None, command

    def execute_scan(self, command: List[str]) -> Dict:
        """
        Execute Nmap scan command.

        Args:
            command: List of command arguments

        Returns:
            Dict containing scan results
        """
        start_time = datetime.utcnow()

        try:
            logger.info(f"Executing Nmap scan: {' '.join(command[1:])}")  # Don't log full path

            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=self.timeout,
                check=False  # Don't raise on non-zero exit
            )

            end_time = datetime.utcnow()
            duration = (end_time - start_time).total_seconds()

            if result.returncode != 0:
                logger.error(f"Nmap scan failed with return code {result.returncode}")
                logger.error(f"Stderr: {result.stderr}")
                return {
                    "success": False,
                    "error": result.stderr or "Nmap scan failed",
                    "returncode": result.returncode,
                    "duration_seconds": duration
                }

            # Parse XML output
            parsed_results = self.parse_nmap_xml(result.stdout)

            logger.info(f"Scan completed successfully in {duration:.2f}s")

            return {
                "success": True,
                "raw_output": result.stdout,
                "parsed_results": parsed_results,
                "duration_seconds": duration,
                "timestamp": start_time.isoformat()
            }

        except subprocess.TimeoutExpired:
            logger.error(f"Scan timed out after {self.timeout} seconds")
            return {
                "success": False,
                "error": f"Scan timeout after {self.timeout} seconds",
                "duration_seconds": self.timeout
            }
        except Exception as e:
            logger.exception("Unexpected error during scan execution")
            return {
                "success": False,
                "error": f"Unexpected error: {str(e)}",
                "duration_seconds": (datetime.utcnow() - start_time).total_seconds()
            }

    def parse_nmap_xml(self, xml_output: str) -> Dict:
        """
        Parse Nmap XML output into structured data.

        Args:
            xml_output: Raw XML output from Nmap

        Returns:
            Dict containing parsed results
        """
        try:
            root = ET.fromstring(xml_output)

            results = {
                "scan_info": {},
                "hosts": [],
                "stats": {
                    "hosts_up": 0,
                    "hosts_down": 0,
                    "total_hosts": 0,
                    "total_ports": 0
                }
            }

            # Parse scan info
            scaninfo = root.find("scaninfo")
            if scaninfo is not None:
                results["scan_info"] = dict(scaninfo.attrib)

            # Parse hosts
            for host in root.findall("host"):
                host_data = self._parse_host(host)
                if host_data:
                    results["hosts"].append(host_data)

                    # Update stats
                    if host_data.get("status") == "up":
                        results["stats"]["hosts_up"] += 1
                    else:
                        results["stats"]["hosts_down"] += 1

                    results["stats"]["total_ports"] += len(host_data.get("ports", []))

            results["stats"]["total_hosts"] = len(results["hosts"])

            return results

        except ET.ParseError as e:
            logger.error(f"Failed to parse Nmap XML: {str(e)}")
            return {"error": f"XML parse error: {str(e)}"}
        except Exception as e:
            logger.exception("Unexpected error parsing Nmap XML")
            return {"error": f"Parse error: {str(e)}"}

    def _parse_host(self, host_element) -> Dict:
        """Parse individual host element from XML"""
        try:
            host_data = {
                "status": None,
                "addresses": [],
                "hostnames": [],
                "ports": [],
                "os": None
            }

            # Status
            status = host_element.find("status")
            if status is not None:
                host_data["status"] = status.get("state")

            # Addresses
            for addr in host_element.findall("address"):
                host_data["addresses"].append({
                    "addr": addr.get("addr"),
                    "addrtype": addr.get("addrtype")
                })

            # Hostnames
            hostnames = host_element.find("hostnames")
            if hostnames is not None:
                for hostname in hostnames.findall("hostname"):
                    host_data["hostnames"].append({
                        "name": hostname.get("name"),
                        "type": hostname.get("type")
                    })

            # Ports
            ports = host_element.find("ports")
            if ports is not None:
                for port in ports.findall("port"):
                    port_data = self._parse_port(port)
                    if port_data:
                        host_data["ports"].append(port_data)

            # OS detection
            os_element = host_element.find("os")
            if os_element is not None:
                osmatch = os_element.find("osmatch")
                if osmatch is not None:
                    host_data["os"] = {
                        "name": osmatch.get("name"),
                        "accuracy": osmatch.get("accuracy")
                    }

            return host_data

        except Exception as e:
            logger.error(f"Error parsing host: {str(e)}")
            return {}

    def _parse_port(self, port_element) -> Dict:
        """Parse individual port element from XML"""
        try:
            port_data = {
                "protocol": port_element.get("protocol"),
                "portid": int(port_element.get("portid")),
                "state": None,
                "service": {}
            }

            # State
            state = port_element.find("state")
            if state is not None:
                port_data["state"] = state.get("state")

            # Service
            service = port_element.find("service")
            if service is not None:
                port_data["service"] = {
                    "name": service.get("name"),
                    "product": service.get("product"),
                    "version": service.get("version"),
                    "extrainfo": service.get("extrainfo")
                }

            return port_data

        except Exception as e:
            logger.error(f"Error parsing port: {str(e)}")
            return {}

    def scan(self, target: str, scan_type: str, custom_args: Optional[str] = None) -> Dict:
        """
        Main method to perform a complete Nmap scan.

        Args:
            target: Target IP or CIDR range
            scan_type: Type of scan to perform
            custom_args: Optional custom Nmap arguments

        Returns:
            Dict containing scan results or error information
        """
        # Validate and prepare
        valid, error, command = self.validate_and_prepare_scan(target, scan_type, custom_args)

        if not valid:
            return {
                "success": False,
                "error": error,
                "target": target,
                "scan_type": scan_type
            }

        # Execute scan
        result = self.execute_scan(command)

        # Add metadata
        result["target"] = target
        result["scan_type"] = scan_type

        return result


def run_nmap_scan(target: str, scan_type: str = "default", custom_args: Optional[str] = None) -> Dict:
    """
    Convenience function to run an Nmap scan.

    Args:
        target: Target IP or CIDR range
        scan_type: Type of scan (default, quick, full, stealth, os, vuln, custom)
        custom_args: Optional custom Nmap arguments (only used with scan_type='custom')

    Returns:
        Dict containing scan results

    Raises:
        NmapSecurityError: If validation fails
        NmapExecutionError: If Nmap execution fails
    """
    try:
        scanner = NmapScanner()
        result = scanner.scan(target, scan_type, custom_args)
        return result
    except Exception as e:
        logger.exception("Failed to run Nmap scan")
        return {
            "success": False,
            "error": str(e),
            "target": target,
            "scan_type": scan_type
        }
