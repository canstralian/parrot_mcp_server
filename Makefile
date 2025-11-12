# Makefile for Parrot MCP Server Integration Tests
.PHONY: help test test-fast test-integration test-security test-coverage clean install lint format

# Default target
.DEFAULT_GOAL := help

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
NC=\033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Parrot MCP Server - Test Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

install: ## Install test dependencies
	@echo "$(GREEN)Installing test dependencies...$(NC)"
	pip install -r requirements-test.txt

test: ## Run all tests
	@echo "$(GREEN)Running all tests...$(NC)"
	pytest -v

test-fast: ## Run tests excluding slow tests
	@echo "$(GREEN)Running fast tests only...$(NC)"
	pytest -v -m "not slow"

test-critical: ## Run critical priority tests only
	@echo "$(GREEN)Running critical tests...$(NC)"
	pytest -v -m "critical"

test-api: ## Run API endpoint tests
	@echo "$(GREEN)Running API endpoint tests...$(NC)"
	pytest -v -m "api" tests/integration/test_api_endpoints.py

test-integration: ## Run tool integration tests
	@echo "$(GREEN)Running tool integration tests...$(NC)"
	pytest -v tests/integration/test_tool_integration.py

test-security: ## Run security tests
	@echo "$(GREEN)Running security tests...$(NC)"
	pytest -v -m "security" tests/integration/test_security.py

test-concurrency: ## Run concurrency tests
	@echo "$(GREEN)Running concurrency tests...$(NC)"
	pytest -v -m "concurrency" tests/integration/test_concurrency.py

test-edge-cases: ## Run edge case tests
	@echo "$(GREEN)Running edge case tests...$(NC)"
	pytest -v tests/integration/test_edge_cases.py

test-coverage: ## Run tests with coverage report
	@echo "$(GREEN)Running tests with coverage...$(NC)"
	pytest --cov=. --cov-report=html --cov-report=term --cov-report=xml

test-coverage-html: test-coverage ## Generate HTML coverage report and open it
	@echo "$(GREEN)Opening coverage report...$(NC)"
	@command -v xdg-open > /dev/null && xdg-open htmlcov/index.html || \
	command -v open > /dev/null && open htmlcov/index.html || \
	echo "Please open htmlcov/index.html in your browser"

test-parallel: ## Run tests in parallel (requires pytest-xdist)
	@echo "$(GREEN)Running tests in parallel...$(NC)"
	pytest -v -n auto

test-verbose: ## Run tests with maximum verbosity
	@echo "$(GREEN)Running tests with verbose output...$(NC)"
	pytest -vv -s

test-failed: ## Re-run only failed tests from last run
	@echo "$(GREEN)Re-running failed tests...$(NC)"
	pytest --lf -v

test-exitfirst: ## Stop on first test failure
	@echo "$(GREEN)Running tests (stop on first failure)...$(NC)"
	pytest -x -v

test-keyword: ## Run tests matching keyword (usage: make test-keyword KEYWORD=nmap)
	@echo "$(GREEN)Running tests matching: $(KEYWORD)$(NC)"
	pytest -v -k "$(KEYWORD)"

test-markers: ## Show available test markers
	@echo "$(GREEN)Available test markers:$(NC)"
	@pytest --markers

test-collect-only: ## Show which tests would be run without running them
	@echo "$(GREEN)Collecting tests...$(NC)"
	pytest --collect-only

lint: ## Run code linting
	@echo "$(GREEN)Running linters...$(NC)"
	@command -v flake8 > /dev/null && flake8 tests/ || echo "flake8 not installed"
	@command -v mypy > /dev/null && mypy tests/ --ignore-missing-imports || echo "mypy not installed"

format: ## Format code with black
	@echo "$(GREEN)Formatting code...$(NC)"
	@command -v black > /dev/null && black tests/ || echo "black not installed"

clean: ## Clean test artifacts and cache
	@echo "$(GREEN)Cleaning test artifacts...$(NC)"
	rm -rf .pytest_cache
	rm -rf htmlcov
	rm -rf .coverage
	rm -rf coverage.xml
	rm -rf .mypy_cache
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete

report: ## Generate and display test report
	@echo "$(GREEN)Generating test report...$(NC)"
	pytest --html=report.html --self-contained-html
	@echo "$(GREEN)Report saved to report.html$(NC)"

ci: ## Run CI test suite (what runs in GitHub Actions)
	@echo "$(GREEN)Running CI test suite...$(NC)"
	pytest -v --cov=. --cov-report=xml --cov-fail-under=85

check: lint test ## Run linting and tests
	@echo "$(GREEN)All checks passed!$(NC)"

watch: ## Watch for changes and re-run tests
	@echo "$(GREEN)Watching for changes...$(NC)"
	@command -v pytest-watch > /dev/null && ptw || \
	echo "$(RED)pytest-watch not installed. Install with: pip install pytest-watch$(NC)"

# Environment-specific targets
test-local: ## Run tests against local server
	@echo "$(GREEN)Running tests against local server...$(NC)"
	MCP_BASE_URL=http://localhost:5000 pytest -v

test-staging: ## Run tests against staging server
	@echo "$(GREEN)Running tests against staging server...$(NC)"
	MCP_BASE_URL=$(STAGING_URL) pytest -v

# Performance targets
test-benchmark: ## Run performance benchmark tests
	@echo "$(GREEN)Running performance benchmarks...$(NC)"
	pytest -v -m "concurrency" --durations=10

# Documentation targets
docs-tests: ## Generate test documentation
	@echo "$(GREEN)Generating test documentation...$(NC)"
	@pytest --collect-only -q | head -20
	@echo ""
	@echo "Total tests: $$(pytest --collect-only -q | tail -1)"

# Debug targets
test-debug: ## Run tests with debugging enabled
	@echo "$(GREEN)Running tests in debug mode...$(NC)"
	pytest -v -s --pdb

test-trace: ## Run tests with trace enabled
	@echo "$(GREEN)Running tests with trace...$(NC)"
	pytest -v --trace

# Quick health check
health-check: ## Quick health check of test suite
	@echo "$(GREEN)Running health check...$(NC)"
	@pytest tests/integration/test_api_endpoints.py::TestHealthEndpoint -v

# Generate test matrix
test-matrix: ## Show test distribution by category
	@echo "$(GREEN)Test Distribution:$(NC)"
	@echo "  API Tests:         $$(pytest --collect-only -q -m api 2>/dev/null | tail -1 || echo 'N/A')"
	@echo "  Security Tests:    $$(pytest --collect-only -q -m security 2>/dev/null | tail -1 || echo 'N/A')"
	@echo "  Integration Tests: $$(pytest --collect-only -q -m integration 2>/dev/null | tail -1 || echo 'N/A')"
	@echo "  Concurrency Tests: $$(pytest --collect-only -q -m concurrency 2>/dev/null | tail -1 || echo 'N/A')"
	@echo "  Edge Case Tests:   $$(pytest --collect-only -q -m edge_case 2>/dev/null | tail -1 || echo 'N/A')"
