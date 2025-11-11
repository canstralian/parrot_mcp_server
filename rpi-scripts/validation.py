#!/usr/bin/env python3
"""
validation.py - Input validation utilities for Parrot MCP Server

This module provides reusable validation functions for sanitizing and
validating user-supplied data, particularly IP addresses and port numbers.

Usage:
    from validation import validate_ipv4, validate_port
    
    if validate_ipv4("192.168.1.1"):
        print("Valid IP")
    
    if validate_port(8080):
        print("Valid port")

Security Features:
    - Regex-based validation for IPv4 addresses
    - Port range validation (1-65535)
    - Descriptive error messages for invalid input
    - No external dependencies beyond standard library
"""

import re
import sys
from typing import Union


def validate_ipv4(ip_address: str) -> bool:
    """
    Validate an IPv4 address.
    
    Args:
        ip_address: String containing the IP address to validate
        
    Returns:
        True if valid IPv4 address, False otherwise
        
    Examples:
        >>> validate_ipv4("192.168.1.1")
        True
        >>> validate_ipv4("256.1.1.1")
        False
        >>> validate_ipv4("not.an.ip.address")
        False
    """
    if not isinstance(ip_address, str):
        return False
    
    # IPv4 address regex pattern
    # Each octet must be 0-255
    ipv4_pattern = re.compile(
        r'^('
        r'(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}'
        r'(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
        r'$'
    )
    
    return bool(ipv4_pattern.match(ip_address))


def validate_port(port: Union[int, str]) -> bool:
    """
    Validate a network port number (1-65535).
    
    Args:
        port: Port number as integer or string
        
    Returns:
        True if valid port number, False otherwise
        
    Examples:
        >>> validate_port(8080)
        True
        >>> validate_port("3000")
        True
        >>> validate_port(0)
        False
        >>> validate_port(70000)
        False
        >>> validate_port("not_a_port")
        False
    """
    try:
        port_num = int(port)
        return 1 <= port_num <= 65535
    except (ValueError, TypeError):
        return False


def validate_email(email: str) -> bool:
    """
    Validate an email address.
    
    Args:
        email: String containing the email address to validate
        
    Returns:
        True if valid email format, False otherwise
        
    Examples:
        >>> validate_email("user@example.com")
        True
        >>> validate_email("invalid.email")
        False
    """
    if not isinstance(email, str):
        return False
    
    email_pattern = re.compile(
        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    )
    
    return bool(email_pattern.match(email))


def sanitize_input(input_str: str, max_length: int = 1048576) -> str:
    """
    Sanitize input string by removing dangerous characters.
    
    Removes null bytes, carriage returns, and non-printable characters
    (except newlines and tabs).
    
    Args:
        input_str: String to sanitize
        max_length: Maximum allowed length (default: 1MB)
        
    Returns:
        Sanitized string
        
    Raises:
        ValueError: If input exceeds max_length
    """
    if len(input_str) > max_length:
        raise ValueError(
            f"Input exceeds maximum length: {len(input_str)} > {max_length}"
        )
    
    # Remove null bytes and carriage returns
    sanitized = input_str.replace('\0', '').replace('\r', '')
    
    # Keep only printable characters, newlines, and tabs
    sanitized = ''.join(
        char for char in sanitized
        if char.isprintable() or char in '\n\t'
    )
    
    return sanitized


def main():
    """
    Command-line interface for validation functions.
    
    Usage:
        python3 validation.py ipv4 192.168.1.1
        python3 validation.py port 8080
        python3 validation.py email user@example.com
    """
    if len(sys.argv) < 3:
        print("Usage: validation.py <type> <value>", file=sys.stderr)
        print("Types: ipv4, port, email", file=sys.stderr)
        sys.exit(1)
    
    validation_type = sys.argv[1].lower()
    value = sys.argv[2]
    
    validators = {
        'ipv4': validate_ipv4,
        'port': validate_port,
        'email': validate_email,
    }
    
    if validation_type not in validators:
        print(f"Error: Unknown validation type: {validation_type}", file=sys.stderr)
        print(f"Valid types: {', '.join(validators.keys())}", file=sys.stderr)
        sys.exit(1)
    
    validator = validators[validation_type]
    
    if validator(value):
        print(f"✓ Valid {validation_type}: {value}")
        sys.exit(0)
    else:
        print(f"✗ Invalid {validation_type}: {value}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
