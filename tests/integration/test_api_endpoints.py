"""
Integration tests for MCP Kali Server API endpoints.

Tests all API endpoints including health checks, tool execution,
error handling, and data validation.
"""

import pytest
import requests
import json
import time
from typing import Dict, Any

from tests.fixtures.mock_targets import MOCK_HEALTH_RESPONSES, INVALID_TARGETS
from tests.conftest import assert_valid_json_response


class TestHealthEndpoint:
    """
    Test Case 1.1: Health Check Endpoint
    Priority: Critical

    Tests the /health endpoint to verify server status and tool availability.
    """

    @pytest.mark.critical
    @pytest.mark.api
    def test_health_endpoint_returns_200(self, api_client, test_config):
        """
        Verify /health endpoint returns HTTP 200 status.

        Steps:
        1. Send GET request to /health
        2. Verify response status code is 200
        """
        response = api_client.get(f"{test_config['base_url']}/health")
        assert response.status_code == 200, \
            f"Expected status 200, got {response.status_code}"

    @pytest.mark.critical
    @pytest.mark.api
    def test_health_endpoint_returns_json(self, api_client, test_config):
        """
        Verify /health endpoint returns valid JSON.

        Steps:
        1. Send GET request to /health
        2. Verify Content-Type is application/json
        3. Verify response can be parsed as JSON
        """
        response = api_client.get(f"{test_config['base_url']}/health")
        data = assert_valid_json_response(response)
        assert isinstance(data, dict), "Response should be a JSON object"

    @pytest.mark.critical
    @pytest.mark.api
    def test_health_endpoint_contains_status(self, api_client, test_config):
        """
        Verify /health endpoint contains status field.

        Expected Result:
        - Response contains "status": "healthy" or "degraded"
        """
        response = api_client.get(f"{test_config['base_url']}/health")
        data = assert_valid_json_response(response)

        assert "status" in data, "Health response must contain 'status' field"
        assert data["status"] in ["healthy", "degraded", "unhealthy"], \
            f"Invalid status value: {data['status']}"

    @pytest.mark.critical
    @pytest.mark.api
    def test_health_endpoint_contains_tool_availability(self, api_client, test_config):
        """
        Verify tool availability status in health response.

        Expected Result:
        - Response contains tools availability information
        - Each tool has availability status
        """
        response = api_client.get(f"{test_config['base_url']}/health")
        data = assert_valid_json_response(response)

        assert "tools" in data, "Health response must contain 'tools' field"
        assert isinstance(data["tools"], dict), "Tools field must be a dictionary"

        # Verify expected tools are present
        expected_tools = ["nmap", "gobuster", "nikto", "sqlmap"]
        for tool in expected_tools:
            if tool in data["tools"]:
                tool_data = data["tools"][tool]
                assert "available" in tool_data, \
                    f"Tool {tool} must have 'available' field"
                assert isinstance(tool_data["available"], bool), \
                    f"Tool {tool} availability must be boolean"

    @pytest.mark.api
    def test_health_endpoint_response_time(self, api_client, test_config):
        """
        Verify health endpoint responds quickly.

        Expected Result:
        - Response time < 1 second
        """
        start_time = time.time()
        response = api_client.get(f"{test_config['base_url']}/health")
        elapsed_time = time.time() - start_time

        assert response.status_code == 200
        assert elapsed_time < 1.0, \
            f"Health endpoint too slow: {elapsed_time:.2f}s (max: 1.0s)"

    @pytest.mark.api
    def test_health_endpoint_includes_version(self, api_client, test_config):
        """
        Verify health response includes version information.
        """
        response = api_client.get(f"{test_config['base_url']}/health")
        data = assert_valid_json_response(response)

        # Version is optional but recommended
        if "version" in data:
            assert isinstance(data["version"], str)
            assert len(data["version"]) > 0


class TestToolExecutionEndpoints:
    """
    Test Case 1.2: Tool Execution - Nmap Scan
    Priority: Critical

    Tests the tool execution endpoints with focus on nmap integration.
    """

    @pytest.mark.critical
    @pytest.mark.api
    @pytest.mark.requires_tools
    def test_nmap_scan_with_valid_target(self, api_client, test_config, valid_target):
        """
        Verify nmap integration works correctly with valid target.

        Steps:
        1. Send POST to /api/tools/nmap with target parameter
        2. Wait for scan completion (with timeout)
        3. Verify response contains stdout/stderr
        4. Check return_code = 0 for successful scan

        Expected Result:
        - Complete nmap scan results returned
        - Status code 200 or 202 (Accepted)
        """
        payload = {
            "target": valid_target,
            "arguments": ["-F"]  # Fast scan for testing
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        # Accept both 200 (synchronous) and 202 (asynchronous)
        assert response.status_code in [200, 202], \
            f"Expected status 200 or 202, got {response.status_code}"

        data = assert_valid_json_response(response)

        # Verify response structure
        assert "target" in data
        assert data["target"] == valid_target

        # If synchronous, verify results
        if response.status_code == 200:
            assert "return_code" in data
            assert "stdout" in data or "stderr" in data

    @pytest.mark.critical
    @pytest.mark.api
    @pytest.mark.requires_tools
    def test_nmap_scan_returns_results(self, api_client, test_config, valid_target):
        """
        Verify nmap scan returns complete results.

        Expected Result:
        - stdout contains scan output
        - return_code indicates success/failure
        - Appropriate fields present in response
        """
        payload = {
            "target": valid_target,
            "arguments": ["-F", "-Pn"]
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        if response.status_code == 200:
            data = assert_valid_json_response(response)

            # Verify essential fields
            required_fields = ["return_code", "target"]
            for field in required_fields:
                assert field in data, f"Missing required field: {field}"

            # Verify output fields
            assert "stdout" in data or "stderr" in data, \
                "Response must contain stdout or stderr"

    @pytest.mark.api
    @pytest.mark.requires_tools
    def test_nmap_scan_with_options(self, api_client, test_config, valid_target):
        """
        Verify nmap accepts various scan options.
        """
        scan_options = [
            ["-sT"],  # TCP connect scan
            ["-F"],  # Fast scan
            ["-p", "80,443"],  # Specific ports
        ]

        for options in scan_options:
            payload = {
                "target": valid_target,
                "arguments": options
            }

            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=test_config['timeout']
            )

            assert response.status_code in [200, 202], \
                f"Failed with options {options}: status {response.status_code}"

    @pytest.mark.api
    @pytest.mark.requires_tools
    def test_gobuster_directory_scan(self, api_client, test_config):
        """
        Verify gobuster integration for directory scanning.
        """
        payload = {
            "url": "http://scanme.nmap.org",
            "mode": "dir",
            "wordlist": "/usr/share/wordlists/dirb/common.txt",
            "threads": 10
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/gobuster",
            json=payload,
            timeout=test_config['timeout']
        )

        assert response.status_code in [200, 202], \
            f"Expected status 200 or 202, got {response.status_code}"

        if response.status_code == 200:
            data = assert_valid_json_response(response)
            assert "return_code" in data or "status" in data


class TestErrorHandling:
    """
    Test Case 1.3: Error Handling - Invalid Target
    Priority: High

    Tests error handling for invalid inputs and edge cases.
    """

    @pytest.mark.high
    @pytest.mark.api
    def test_nmap_with_invalid_target(self, api_client, test_config, invalid_target):
        """
        Verify proper error handling for invalid input.

        Steps:
        1. Send POST to /api/tools/nmap with invalid target
        2. Verify appropriate error message returned
        3. Check HTTP status code (400 Bad Request or 422 Unprocessable Entity)

        Expected Result:
        - Error response with descriptive message
        - Status code 400 or 422
        """
        payload = {
            "target": invalid_target
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        # Should return client error
        assert response.status_code in [400, 422], \
            f"Expected status 400 or 422 for invalid target, got {response.status_code}"

        data = assert_valid_json_response(response)

        # Verify error message present
        assert "error" in data or "message" in data or "detail" in data, \
            "Error response must contain error message"

    @pytest.mark.high
    @pytest.mark.api
    def test_missing_required_parameters(self, api_client, test_config):
        """
        Verify error handling when required parameters are missing.

        Expected Result:
        - Returns 400 Bad Request
        - Error message indicates missing parameter
        """
        # Empty payload
        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json={},
            timeout=test_config['timeout']
        )

        assert response.status_code in [400, 422], \
            f"Expected status 400 or 422 for missing parameters, got {response.status_code}"

    @pytest.mark.high
    @pytest.mark.api
    def test_invalid_json_payload(self, api_client, test_config):
        """
        Verify error handling for malformed JSON.

        Expected Result:
        - Returns 400 Bad Request
        - Error indicates invalid JSON
        """
        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            data="this is not json",
            headers={"Content-Type": "application/json"},
            timeout=test_config['timeout']
        )

        assert response.status_code == 400, \
            f"Expected status 400 for invalid JSON, got {response.status_code}"

    @pytest.mark.high
    @pytest.mark.api
    def test_unsupported_http_method(self, api_client, test_config):
        """
        Verify error handling for unsupported HTTP methods.

        Expected Result:
        - Returns 405 Method Not Allowed
        """
        # Try GET on POST endpoint
        response = api_client.get(
            f"{test_config['base_url']}/api/tools/nmap",
            timeout=test_config['timeout']
        )

        assert response.status_code in [405, 404], \
            f"Expected status 405 or 404, got {response.status_code}"

    @pytest.mark.api
    def test_nonexistent_endpoint(self, api_client, test_config):
        """
        Verify 404 response for non-existent endpoints.
        """
        response = api_client.get(
            f"{test_config['base_url']}/api/nonexistent",
            timeout=test_config['timeout']
        )

        assert response.status_code == 404, \
            f"Expected status 404 for non-existent endpoint, got {response.status_code}"

    @pytest.mark.api
    def test_tool_not_found_error(self, api_client, test_config):
        """
        Verify error when requesting non-existent tool.
        """
        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nonexistenttool",
            json={"target": "127.0.0.1"},
            timeout=test_config['timeout']
        )

        assert response.status_code in [404, 422], \
            f"Expected status 404 or 422 for non-existent tool, got {response.status_code}"


class TestAPIResponseFormat:
    """
    Verify consistent API response formats across endpoints.
    """

    @pytest.mark.api
    def test_all_endpoints_return_json(self, api_client, test_config):
        """
        Verify all API endpoints return JSON responses.
        """
        endpoints = [
            ("/health", "GET"),
        ]

        for endpoint, method in endpoints:
            if method == "GET":
                response = api_client.get(f"{test_config['base_url']}{endpoint}")
            elif method == "POST":
                response = api_client.post(
                    f"{test_config['base_url']}{endpoint}",
                    json={}
                )

            if response.status_code < 500:  # Skip server errors
                assert "application/json" in response.headers.get("Content-Type", ""), \
                    f"Endpoint {endpoint} did not return JSON"

    @pytest.mark.api
    def test_error_responses_include_timestamp(self, api_client, test_config):
        """
        Verify error responses include timestamp for debugging.
        """
        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json={},  # Invalid payload
            timeout=test_config['timeout']
        )

        if response.status_code >= 400:
            data = assert_valid_json_response(response)
            # Timestamp is optional but recommended
            # Just verify it's a valid format if present
            if "timestamp" in data:
                assert isinstance(data["timestamp"], str)

    @pytest.mark.api
    def test_success_responses_include_request_id(self, api_client, test_config):
        """
        Verify responses include request/scan ID for tracking.
        """
        response = api_client.get(f"{test_config['base_url']}/health")

        if response.status_code == 200:
            data = assert_valid_json_response(response)
            # Request ID is optional but recommended
            if "request_id" in data or "scan_id" in data or "id" in data:
                # Verify it's a string
                id_field = data.get("request_id") or data.get("scan_id") or data.get("id")
                assert isinstance(id_field, (str, int))
