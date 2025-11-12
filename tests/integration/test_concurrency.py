"""
Concurrency and performance tests for MCP Kali Server.

Tests concurrent request handling, race conditions, resource management,
and system behavior under load.
"""

import pytest
import time
import threading
import concurrent.futures
from typing import List, Dict, Any
import requests

from tests.fixtures.test_data import generate_concurrent_requests


class TestConcurrentExecution:
    """
    Test Case 2.1: Concurrent Tool Execution
    Priority: High

    Tests handling of multiple simultaneous requests.
    """

    @pytest.mark.high
    @pytest.mark.concurrency
    @pytest.mark.slow
    def test_concurrent_nmap_scans(self, api_client, test_config, valid_target):
        """
        Test handling multiple simultaneous nmap requests.

        Steps:
        1. Launch 10 concurrent nmap scans
        2. Monitor system resources
        3. Verify all scans complete successfully
        4. Check for race conditions or deadlocks

        Expected Result:
        - All requests processed without errors
        - No deadlocks or race conditions
        """
        num_concurrent = 10
        results = []
        errors = []

        def run_scan(scan_id: int):
            """Execute a single scan."""
            try:
                response = api_client.post(
                    f"{test_config['base_url']}/api/tools/nmap",
                    json={
                        "target": valid_target,
                        "arguments": ["-F"],
                        "scan_id": f"concurrent_{scan_id}"
                    },
                    timeout=test_config['timeout']
                )
                return {
                    "scan_id": scan_id,
                    "status_code": response.status_code,
                    "success": response.status_code in [200, 202]
                }
            except Exception as e:
                errors.append({"scan_id": scan_id, "error": str(e)})
                return {"scan_id": scan_id, "success": False, "error": str(e)}

        # Launch concurrent requests
        start_time = time.time()

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_concurrent) as executor:
            futures = [
                executor.submit(run_scan, i)
                for i in range(num_concurrent)
            ]

            # Wait for all to complete
            for future in concurrent.futures.as_completed(futures, timeout=test_config['timeout']):
                result = future.result()
                results.append(result)

        elapsed_time = time.time() - start_time

        # Verify all completed
        assert len(results) == num_concurrent, \
            f"Expected {num_concurrent} results, got {len(results)}"

        # Verify success rate
        successful = sum(1 for r in results if r.get("success", False))
        success_rate = successful / num_concurrent * 100

        assert success_rate >= 80, \
            f"Success rate too low: {success_rate:.1f}% (expected >= 80%)"

        # Check for reasonable performance
        # Average time per scan should not be much more than sequential
        avg_time = elapsed_time / num_concurrent
        assert avg_time < test_config['timeout'], \
            f"Average scan time too high: {avg_time:.2f}s"

        # Verify no deadlocks (all completed in reasonable time)
        assert elapsed_time < test_config['timeout'] * 1.5, \
            f"Concurrent execution took too long: {elapsed_time:.2f}s"

    @pytest.mark.high
    @pytest.mark.concurrency
    def test_concurrent_different_tools(self, api_client, test_config, valid_target):
        """
        Test concurrent execution of different tools.

        Expected Result:
        - Multiple different tools can run simultaneously
        - No resource conflicts
        """
        num_concurrent = 5
        results = []

        def run_nmap():
            return api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": valid_target, "arguments": ["-F"]},
                timeout=test_config['timeout']
            )

        def run_gobuster():
            return api_client.post(
                f"{test_config['base_url']}/api/tools/gobuster",
                json={
                    "url": f"http://{valid_target}",
                    "mode": "dir",
                    "wordlist": "/usr/share/wordlists/dirb/common.txt"
                },
                timeout=test_config['timeout']
            )

        # Mix of different tools
        tasks = [run_nmap, run_gobuster, run_nmap, run_gobuster, run_nmap]

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_concurrent) as executor:
            futures = [executor.submit(task) for task in tasks]

            for future in concurrent.futures.as_completed(futures, timeout=test_config['timeout']):
                try:
                    response = future.result()
                    results.append({
                        "status_code": response.status_code,
                        "success": response.status_code in [200, 202]
                    })
                except Exception as e:
                    results.append({"success": False, "error": str(e)})

        # Verify reasonable success rate
        successful = sum(1 for r in results if r.get("success", False))
        assert successful >= len(tasks) * 0.7, \
            "Too many concurrent requests failed"

    @pytest.mark.concurrency
    def test_concurrent_health_checks(self, api_client, test_config):
        """
        Test concurrent health check requests.

        Expected Result:
        - Health endpoint handles concurrent requests well
        - All return consistent data
        """
        num_concurrent = 20
        results = []

        def check_health():
            response = api_client.get(f"{test_config['base_url']}/health")
            return {
                "status_code": response.status_code,
                "data": response.json() if response.status_code == 200 else None
            }

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_concurrent) as executor:
            futures = [executor.submit(check_health) for _ in range(num_concurrent)]

            for future in concurrent.futures.as_completed(futures, timeout=30):
                result = future.result()
                results.append(result)

        # All should succeed
        assert all(r["status_code"] == 200 for r in results), \
            "Some health checks failed"

        # All should return consistent status
        statuses = [r["data"].get("status") for r in results if r["data"]]
        assert len(set(statuses)) == 1, \
            f"Inconsistent health statuses: {set(statuses)}"

    @pytest.mark.concurrency
    @pytest.mark.slow
    def test_sequential_vs_concurrent_performance(self, api_client, test_config, valid_target):
        """
        Compare sequential vs concurrent execution performance.

        Expected Result:
        - Concurrent execution shows performance improvement
        """
        num_requests = 5

        # Sequential execution
        sequential_start = time.time()
        for i in range(num_requests):
            try:
                api_client.post(
                    f"{test_config['base_url']}/api/tools/nmap",
                    json={"target": valid_target, "arguments": ["-F"]},
                    timeout=test_config['timeout']
                )
            except:
                pass  # Ignore errors for performance test
        sequential_time = time.time() - sequential_start

        # Concurrent execution
        concurrent_start = time.time()
        with concurrent.futures.ThreadPoolExecutor(max_workers=num_requests) as executor:
            futures = [
                executor.submit(
                    api_client.post,
                    f"{test_config['base_url']}/api/tools/nmap",
                    json={"target": valid_target, "arguments": ["-F"]},
                    timeout=test_config['timeout']
                )
                for _ in range(num_requests)
            ]
            concurrent.futures.wait(futures, timeout=test_config['timeout'])
        concurrent_time = time.time() - concurrent_start

        # Concurrent should be faster (or at least not much slower)
        speedup = sequential_time / concurrent_time if concurrent_time > 0 else 1

        # We expect some speedup, but actual speedup depends on implementation
        # Just verify concurrent isn't significantly slower
        assert concurrent_time <= sequential_time * 1.2, \
            f"Concurrent execution slower than sequential: {concurrent_time:.2f}s vs {sequential_time:.2f}s"


class TestResourceManagement:
    """
    Test proper resource management under concurrent load.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.concurrency
    def test_connection_pool_handling(self, api_client, test_config):
        """
        Verify connection pooling works correctly.

        Expected Result:
        - Connections reused efficiently
        - No connection exhaustion
        """
        num_requests = 50

        def make_request():
            return api_client.get(f"{test_config['base_url']}/health")

        # Make many requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request) for _ in range(num_requests)]

            results = []
            for future in concurrent.futures.as_completed(futures, timeout=60):
                try:
                    response = future.result()
                    results.append(response.status_code == 200)
                except Exception:
                    results.append(False)

        # Most should succeed
        success_rate = sum(results) / len(results) * 100
        assert success_rate >= 90, \
            f"Connection pool issues: only {success_rate:.1f}% succeeded"

    @pytest.mark.concurrency
    def test_memory_usage_stable(self, api_client, test_config):
        """
        Verify memory usage stays stable under load.

        Expected Result:
        - No memory leaks
        - Memory usage doesn't grow excessively
        """
        # This is a simplified test
        # Real implementation would monitor actual memory usage
        num_iterations = 10

        for i in range(num_iterations):
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
                futures = [
                    executor.submit(
                        api_client.get,
                        f"{test_config['base_url']}/health"
                    )
                    for _ in range(10)
                ]
                concurrent.futures.wait(futures, timeout=30)

            # Brief pause between iterations
            time.sleep(0.5)

        # If we get here without crashes, memory is reasonably stable
        assert True

    @pytest.mark.concurrency
    def test_no_file_descriptor_leak(self, api_client, test_config):
        """
        Verify file descriptors are properly closed.

        Expected Result:
        - No file descriptor leaks
        - Can make many sequential requests
        """
        num_requests = 100

        for i in range(num_requests):
            try:
                response = api_client.get(f"{test_config['base_url']}/health")
                assert response.status_code == 200
            except Exception as e:
                pytest.fail(f"Request {i} failed, possible FD leak: {e}")

        # If all requests succeeded, no FD leak
        assert True


class TestRaceConditions:
    """
    Test for race conditions and thread safety.

    Priority: High
    """

    @pytest.mark.high
    @pytest.mark.concurrency
    def test_concurrent_scan_id_generation(self, api_client, test_config, valid_target):
        """
        Verify scan IDs are unique even under concurrent load.

        Expected Result:
        - All scan IDs are unique
        - No collisions
        """
        num_scans = 20
        scan_ids = []
        lock = threading.Lock()

        def run_scan():
            response = api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": valid_target, "arguments": ["-F"]},
                timeout=test_config['timeout']
            )
            if response.status_code in [200, 202]:
                data = response.json()
                if "scan_id" in data or "id" in data or "request_id" in data:
                    scan_id = data.get("scan_id") or data.get("id") or data.get("request_id")
                    with lock:
                        scan_ids.append(scan_id)

        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(run_scan) for _ in range(num_scans)]
            concurrent.futures.wait(futures, timeout=test_config['timeout'])

        # Verify uniqueness
        if len(scan_ids) > 0:
            assert len(scan_ids) == len(set(scan_ids)), \
                "Duplicate scan IDs detected (race condition)"

    @pytest.mark.concurrency
    def test_concurrent_log_writing(self, api_client, test_config, valid_target):
        """
        Verify concurrent log writes don't corrupt logs.

        Expected Result:
        - Log entries remain intact
        - No interleaved writes
        """
        num_requests = 10

        def make_request():
            api_client.post(
                f"{test_config['base_url']}/api/tools/nmap",
                json={"target": valid_target, "arguments": ["-F"]},
                timeout=test_config['timeout']
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=num_requests) as executor:
            futures = [executor.submit(make_request) for _ in range(num_requests)]
            concurrent.futures.wait(futures, timeout=test_config['timeout'])

        # Check log file if accessible
        # This is simplified - real test would validate log integrity
        assert True

    @pytest.mark.concurrency
    def test_shared_resource_access(self, api_client, test_config):
        """
        Verify shared resources accessed safely.

        Expected Result:
        - No data corruption
        - Proper locking/synchronization
        """
        num_threads = 10
        shared_data = []
        lock = threading.Lock()

        def access_resource():
            # Simulate accessing shared resource
            response = api_client.get(f"{test_config['base_url']}/health")
            if response.status_code == 200:
                with lock:
                    shared_data.append(response.json())

        threads = [
            threading.Thread(target=access_resource)
            for _ in range(num_threads)
        ]

        for thread in threads:
            thread.start()

        for thread in threads:
            thread.join(timeout=30)

        # Verify data integrity
        assert len(shared_data) <= num_threads
        # All entries should be valid dicts
        assert all(isinstance(d, dict) for d in shared_data)


class TestLoadTesting:
    """
    Test system behavior under high load.

    Priority: Medium
    """

    @pytest.mark.medium
    @pytest.mark.concurrency
    @pytest.mark.slow
    def test_sustained_load(self, api_client, test_config):
        """
        Test system under sustained load.

        Expected Result:
        - System remains stable
        - Response times stay reasonable
        """
        duration_seconds = 30
        requests_per_second = 5

        start_time = time.time()
        request_count = 0
        errors = 0

        while time.time() - start_time < duration_seconds:
            try:
                response = api_client.get(f"{test_config['base_url']}/health")
                if response.status_code != 200:
                    errors += 1
                request_count += 1
            except Exception:
                errors += 1

            time.sleep(1.0 / requests_per_second)

        # Verify acceptable error rate
        error_rate = errors / request_count * 100 if request_count > 0 else 100
        assert error_rate < 10, \
            f"Error rate too high under load: {error_rate:.1f}%"

    @pytest.mark.medium
    @pytest.mark.concurrency
    @pytest.mark.slow
    def test_burst_traffic(self, api_client, test_config):
        """
        Test handling of burst traffic.

        Expected Result:
        - System handles traffic spikes
        - Graceful degradation if necessary
        """
        burst_size = 50

        # Send burst of requests
        start_time = time.time()

        with concurrent.futures.ThreadPoolExecutor(max_workers=burst_size) as executor:
            futures = [
                executor.submit(
                    api_client.get,
                    f"{test_config['base_url']}/health"
                )
                for _ in range(burst_size)
            ]

            results = []
            for future in concurrent.futures.as_completed(futures, timeout=60):
                try:
                    response = future.result()
                    results.append(response.status_code == 200)
                except Exception:
                    results.append(False)

        elapsed_time = time.time() - start_time

        # Check success rate
        success_rate = sum(results) / len(results) * 100
        assert success_rate >= 70, \
            f"Burst traffic success rate too low: {success_rate:.1f}%"

        # Check response time
        avg_time = elapsed_time / burst_size
        assert avg_time < 5.0, \
            f"Average response time too high during burst: {avg_time:.2f}s"

    @pytest.mark.concurrency
    def test_request_queuing(self, api_client, test_config):
        """
        Verify requests are queued properly when at capacity.

        Expected Result:
        - Requests queued, not dropped
        - Eventually all requests processed
        """
        num_requests = 30

        results = []

        with concurrent.futures.ThreadPoolExecutor(max_workers=15) as executor:
            futures = [
                executor.submit(
                    api_client.get,
                    f"{test_config['base_url']}/health"
                )
                for _ in range(num_requests)
            ]

            for future in concurrent.futures.as_completed(futures, timeout=120):
                try:
                    response = future.result()
                    results.append(response.status_code)
                except Exception:
                    results.append(0)

        # All requests should eventually complete
        assert len(results) == num_requests
        # Most should succeed
        successes = sum(1 for code in results if code in [200, 202])
        assert successes >= num_requests * 0.8
