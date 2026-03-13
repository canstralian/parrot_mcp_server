# Parrot MCP Server - Automation Rituals
# Focus: Integrity, Security, and Flow

.PHONY: help init test secure integrity run clean lint

help:
	@echo "Parrot MCP Server - Development Workflow"
	@echo "  init       Install dependencies and setup environment"
	@echo "  test       Run unit tests (BATS for Bash, pytest for Python)"
	@echo "  secure     Run forensic security audits (Bandit, Safety)"
	@echo "  integrity  Generate cryptographic hashes for build artifacts"
	@echo "  lint       Run shellcheck + shfmt on all shell scripts"
	@echo "  run        Spin up the Signal Reactor (Docker)"
	@echo "  clean      Remove build artifacts and caches"

init:
	pip install -r requirements.txt
	cp -n .env.example .env || true

test:
	@echo "--- [Bash Tests: BATS] ---"
	bats rpi-scripts/tests/*.bats
	@echo "--- [Python Tests: pytest] ---"
	pytest --asyncio-mode=auto tests/

secure:
	@echo "--- [Security Core: Adaptive Immunity Audit] ---"
	bandit -r src/ -ll
	safety check
	@echo "--- [Audit Complete] ---"

integrity:
	@echo "--- [Integrity as Ritual: Fingerprinting Artifacts] ---"
	find src/ -type f -exec sha256sum {} + > build_manifest.sha256
	@echo "Manifest created: build_manifest.sha256"

lint:
	@echo "--- [Shell Linting] ---"
	shellcheck rpi-scripts/cli.sh rpi-scripts/scripts/*.sh rpi-scripts/*.sh
	shfmt -w rpi-scripts/cli.sh rpi-scripts/scripts/*.sh rpi-scripts/*.sh

run:
	docker-compose up --build

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -f build_manifest.sha256
