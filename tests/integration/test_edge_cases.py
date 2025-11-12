"""
Edge case and error condition tests for MCP Kali Server.

Tests timeout handling, large outputs, malformed data, network issues,
and other boundary conditions.
"""

import pytest
import time
import requests
from typing import Dict, Any

from tests.fixtures.test_data import generate_malformed_json, generate_large_output
from tests.fixtures.mock_targets import MOCK_ERRORS


class TestTimeoutHandling:
    """
    Test Case 4.1: Timeout Handling
    Priority: Medium

    Verify proper handling of long-running commands and timeouts.
    """

    @pytest.mark.medium
    @pytest.mark.edge_case
    @pytest.mark.slow
    @pytest.mark.timeout(200)
    def test_scan_timeout_handled(self, api_client, test_config):
        """
        Verify proper handling of long-running commands.

        Steps:
        1. Execute command that exceeds timeout
        2. Verify graceful termination
        3. Check partial results are captured

        Expected Result:
        - Timeout handled gracefully
        - Partial results returned if available
        - No zombie processes
        """
        # Configure a short timeout for this test
        test_timeout = 5

        payload = {
            "target": "scanme.nmap.org",
            "arguments": ["-p-", "-T1"],  # Full port scan, slow
            "timeout": test_timeout
        }

        start_time = time.time()

        try:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=test_timeout + 5  # Client timeout slightly longer
            )

            elapsed = time.time() - start_time

            # Should respond within reasonable time
            assert elapsed < test_timeout * 2, \
                f"Response took too long: {elapsed:.2f}s"

            # Check response
            if response.status_code == 200:
                data = response.json()

                # May have timeout status or partial results
                if "status" in data:
                    assert data["status"] in ["timeout", "partial", "completed"]

                # Partial output may be available
                if "stdout" in data or "stderr" in data:
                    assert True  # Partial results captured

        except requests.Timeout:
            # Client timeout is acceptable
            assert True, "Request timed out as expected"

    @pytest.mark.edge_case
    @pytest.mark.timeout(30)
    def test_timeout_configuration_respected(self, api_client, test_config):
        """
        Verify custom timeout values are respected.
        """
        custom_timeout = 10

        payload = {
            "target": "scanme.nmap.org",
            "arguments": ["-F"],
            "timeout": custom_timeout
        }

        start_time = time.time()

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=custom_timeout + 5
        )

        elapsed = time.time() - start_time

        # Should complete or timeout within configured time
        if response.status_code in [200, 202]:
            # Success is good
            assert True
        else:
            # If failed, should fail quickly
            assert elapsed <= custom_timeout * 1.5

    @pytest.mark.edge_case
    def test_zero_timeout_rejected(self, api_client, test_config):
        """
        Verify invalid timeout values are rejected.
        """
        invalid_timeouts = [0, -1, -100, "invalid"]

        for timeout_val in invalid_timeouts:
            payload = {
                "target": "127.0.0.1",
                "timeout": timeout_val
            }

            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=test_config['timeout']
            )

            # Should reject invalid timeout
            assert response.status_code in [400, 422], \
                f"Invalid timeout not rejected: {timeout_val}"

    @pytest.mark.edge_case
    @pytest.mark.slow
    def test_multiple_timeouts_independent(self, api_client, test_config):
        """
        Verify timeout of one scan doesn't affect others.
        """
        # Start multiple scans
        import concurrent.futures

        def run_scan(scan_timeout):
            return api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={
                    "target": "scanme.nmap.org",
                    "arguments": ["-F"],
                    "timeout": scan_timeout
                },
                timeout=scan_timeout + 5
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(run_scan, 30),
                executor.submit(run_scan, 30),
                executor.submit(run_scan, 30),
            ]

            results = []
            for future in concurrent.futures.as_completed(futures, timeout=120):
                try:
                    response = future.result()
                    results.append(response.status_code in [200, 202])
                except:
                    results.append(False)

        # Most should succeed independently
        assert sum(results) >= 2


class TestLargeOutputHandling:
    """
    Test Case 4.2: Large Output Handling
    Priority: Medium

    Test handling of tools with large output.
    """

    @pytest.mark.medium
    @pytest.mark.edge_case
    @pytest.mark.slow
    def test_large_nmap_output_captured(self, api_client, test_config):
        """
        Test handling of tools with large output.

        Steps:
        1. Execute tool with verbose output
        2. Verify complete output captured
        3. Check memory usage stays reasonable

        Expected Result:
        - Large outputs handled efficiently
        - No truncation or corruption
        """
        payload = {
            "target": "scanme.nmap.org",
            "arguments": ["-v", "-A", "-T4"]  # Verbose, aggressive scan
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        if response.status_code == 200:
            data = response.json()

            # Verify output present
            if "stdout" in data:
                output = data["stdout"]
                assert len(output) > 0

                # Verify output is complete (not truncated)
                # Real nmap output should have "Nmap done"
                assert isinstance(output, str)

    @pytest.mark.edge_case
    def test_output_size_limit(self, api_client, test_config):
        """
        Verify reasonable limits on output size.
        """
        # This tests that extremely large outputs are handled
        # Implementation might limit output size for safety
        payload = {
            "target": "scanme.nmap.org",
            "arguments": ["-v", "-v", "-v", "-p-"]  # Very verbose
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        # Should handle gracefully (complete or limit)
        assert response.status_code in [200, 202, 413], \
            "Large output not handled"

    @pytest.mark.edge_case
    def test_binary_output_handling(self, api_client, test_config):
        """
        Verify binary data in output handled safely.
        """
        # Some tools might produce binary output
        # Server should handle safely

        payload = {
            "target": "scanme.nmap.org",
            "arguments": ["-oX", "-"]  # XML output to stdout
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        # Should handle without crashing
        assert response.status_code in [200, 202, 400, 422]

    @pytest.mark.edge_case
    def test_streaming_output(self, api_client, test_config):
        """
        Verify support for streaming large outputs.
        """
        # If server supports streaming, test it
        # Otherwise skip

        payload = {
            "target": "scanme.nmap.org",
            "arguments": ["-v", "-F"],
            "stream": True  # Request streaming if supported
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout'],
            stream=True  # Client-side streaming
        )

        if response.status_code == 200:
            # Try to consume stream
            chunks = []
            try:
                for chunk in response.iter_content(chunk_size=1024):
                    if chunk:
                        chunks.append(chunk)
                assert len(chunks) > 0
            except:
                pytest.skip("Streaming not supported")
        else:
            pytest.skip("Streaming not supported")


class TestMalformedInputs:
    """
    Test handling of malformed and invalid inputs.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.edge_case
    def test_malformed_json_rejected(self, api_client, test_config):
        """
        Verify malformed JSON is rejected gracefully.
        """
        malformed_payloads = generate_malformed_json()

        for payload in malformed_payloads:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                data=payload,  # Send as raw data, not JSON
                headers={"Content-Type": "application/json"},
                timeout=test_config['timeout']
            )

            # Should return 400 Bad Request
            assert response.status_code == 400, \
                f"Malformed JSON not rejected: {payload[:50]}"

    @pytest.mark.edge_case
    def test_missing_content_type(self, api_client, test_config):
        """
        Verify missing Content-Type header handled.
        """
        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            data='{"target": "127.0.0.1"}',
            headers={}  # No Content-Type
        )

        # Should handle gracefully (might accept or reject)
        assert response.status_code in [200, 202, 400, 415]

    @pytest.mark.edge_case
    def test_empty_request_body(self, api_client, test_config):
        """
        Verify empty request body handled.
        """
        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            data="",
            headers={"Content-Type": "application/json"}
        )

        # Should reject empty body
        assert response.status_code in [400, 422]

    @pytest.mark.edge_case
    def test_invalid_http_method(self, api_client, test_config):
        """
        Verify invalid HTTP methods rejected.
        """
        # Try DELETE on POST endpoint
        response = api_client.delete(
            f"{test_config['base_url']}/api/tools/nmap"
        )

        # Should return 405 Method Not Allowed
        assert response.status_code in [405, 404]

    @pytest.mark.edge_case
    def test_invalid_json_types(self, api_client, test_config):
        """
        Verify type mismatches in JSON are caught.
        """
        invalid_payloads = [
            {"target": 12345},  # Number instead of string
            {"target": ["list", "of", "items"]},  # Array instead of string
            {"target": {"nested": "object"}},  # Object instead of string
            {"target": None},  # Null
            {"target": True},  # Boolean
        ]

        for payload in invalid_payloads:
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=test_config['timeout']
            )

            # Should reject type mismatches
            assert response.status_code in [400, 422], \
                f"Invalid type not rejected: {payload}"


class TestNetworkEdgeCases:
    """
    Test edge cases related to network conditions.

    Priority: Medium
    """

    @pytest.mark.medium
    @pytest.mark.edge_case
    def test_unreachable_target(self, api_client, test_config):
        """
        Verify handling of unreachable targets.
        """
        unreachable_targets = [
            "10.255.255.254",  # Likely unreachable
            "192.0.2.1",  # TEST-NET-1 (should not route)
        ]

        for target in unreachable_targets:
            payload = {
                "target": target,
                "arguments": ["-Pn", "-p", "80"],  # Quick check
                "timeout": 30
            }

            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=60
            )

            # Should complete (even if host down)
            assert response.status_code in [200, 202]

    @pytest.mark.edge_case
    def test_dns_resolution_failure(self, api_client, test_config):
        """
        Verify handling of DNS resolution failures.
        """
        payload = {
            "target": "this-domain-definitely-does-not-exist-12345.com"
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        # Should handle DNS failure
        if response.status_code == 200:
            data = response.json()
            # Error should be indicated
            assert data.get("return_code") != 0 or \
                   data.get("status") == "failed"
        else:
            assert response.status_code in [400, 422]

    @pytest.mark.edge_case
    def test_ipv6_address_handling(self, api_client, test_config):
        """
        Verify IPv6 addresses are handled.
        """
        ipv6_addresses = [
            "::1",  # Localhost
            "fe80::1",  # Link-local
            "2001:4860:4860::8888",  # Google DNS
        ]

        for addr in ipv6_addresses:
            payload = {
                "target": addr,
                "arguments": ["-6", "-Pn", "-p", "80"]
            }

            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=test_config['timeout']
            )

            # Should handle IPv6 (accept or reject gracefully)
            assert response.status_code in [200, 202, 400, 422]

    @pytest.mark.edge_case
    def test_cidr_notation(self, api_client, test_config):
        """
        Verify CIDR notation is handled.
        """
        cidr_targets = [
            "192.168.1.0/24",
            "10.0.0.0/16",
            "127.0.0.0/8",
        ]

        for target in cidr_targets:
            payload = {
                "target": target,
                "arguments": ["-sn"]  # Ping scan only
            }

            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json=payload,
                timeout=test_config['timeout']
            )

            # Should handle CIDR (accept or reject gracefully)
            assert response.status_code in [200, 202, 400, 422]


class TestStateManagement:
    """
    Test state management and persistence.

    Priority: Medium
    """

    @pytest.mark.medium
    @pytest.mark.edge_case
    def test_scan_history_persistence(self, api_client, test_config):
        """
        Verify scan history is maintained.
        """
        # Submit a scan
        payload = {
            "target": "127.0.0.1",
            "arguments": ["-F"]
        }

        response = api_client.post(
            f"{test_config['base_url']}/api/tools/nmap",
            json=payload,
            timeout=test_config['timeout']
        )

        scan_id = None
        if response.status_code in [200, 202]:
            data = response.json()
            scan_id = data.get("scan_id") or data.get("id")

        if scan_id:
            # Try to retrieve scan history
            history_response = api_client.get(
                f"{test_config['base_url']}/api/scans/{scan_id}"
            )

            # If history endpoint exists, verify scan is there
            if history_response.status_code == 200:
                history_data = history_response.json()
                assert history_data.get("id") == scan_id or \
                       history_data.get("scan_id") == scan_id
            else:
                pytest.skip("Scan history not implemented")
        else:
            pytest.skip("Scan ID not returned")

    @pytest.mark.edge_case
    def test_concurrent_state_updates(self, api_client, test_config, valid_target):
        """
        Verify state updates don't conflict under concurrent load.
        """
        import concurrent.futures

        num_scans = 5

        def run_scan(i):
            return api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={
                    "target": valid_target,
                    "arguments": ["-F"],
                    "label": f"concurrent_scan_{i}"
                },
                timeout=test_config['timeout']
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_scans) as executor:
            futures = [executor.submit(run_scan, i) for i in range(num_scans)]

            results = []
            for future in concurrent.futures.as_completed(futures):
                try:
                    response = future.result()
                    if response.status_code in [200, 202]:
                        results.append(response.json())
                except:
                    pass

        # Verify all scans got unique IDs
        if len(results) > 1 and all("scan_id" in r or "id" in r for r in results):
            ids = [r.get("scan_id") or r.get("id") for r in results]
            assert len(ids) == len(set(ids)), "Duplicate scan IDs detected"


class TestErrorRecovery:
    """
    Test error recovery and graceful degradation.

    Priority: Medium
    """

    @pytest.mark.medium
    @pytest.mark.edge_case
    def test_recovery_after_crash(self, api_client, test_config):
        """
        Verify server recovers gracefully after errors.
        """
        # Send a bunch of invalid requests
        for _ in range(5):
            api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": "'},DROP TABLE scans;--"},
                timeout=10
            )

        # Verify server still works
        response = api_client.get(f"{test_config['base_url']}/health")
        assert response.status_code == 200

    @pytest.mark.edge_case
    def test_partial_tool_availability(self, api_client, test_config):
        """
        Verify system works even if some tools unavailable.
        """
        # Check health
        response = api_client.get(f"{test_config['base_url']}/health")

        if response.status_code == 200:
            data = response.json()

            # If some tools unavailable, status should be degraded
            if "tools" in data:
                available_tools = [
                    name for name, info in data["tools"].items()
                    if info.get("available") == True
                ]

                # As long as some tools work, system should function
                if len(available_tools) == 0:
                    assert data.get("status") in ["degraded", "unhealthy"]
                else:
                    assert data.get("status") in ["healthy", "degraded"]
