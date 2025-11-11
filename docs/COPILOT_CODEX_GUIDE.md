# Parrot MCP Server Copilot & Codex Configuration Guide

## Purpose and Scope
This guide establishes a unified configuration for GitHub Copilot and Codex within the Parrot MCP Server repository. The objective is to treat Copilot as a disciplined pair programmer that accelerates delivery of a portable, Bash-based Model Context Protocol (MCP) server without compromising security, reliability, or maintainability. These standards govern day-to-day coding practices, automation hooks, and review criteria for the Parrot MCP Server project.

## Behavioral Principles for AI Pair Programmers
- **Role clarity:** Copilot supplies suggestions that must always be reviewed, justified, and attributed to project standards. Human maintainers remain accountable for every merged change.
- **Determinism over creativity:** Prefer predictable, reproducible code that matches existing patterns. Reject speculative or unverified algorithmic variations.
- **Security-first posture:** No credentials, API keys, or proprietary strategies may be suggested or accepted. Default to principle-of-least-privilege and hardened transport (TLS, signed requests, encrypted storage).
- **Data minimization:** Copilot must not introduce telemetry or logging of sensitive protocol data, credentials, or system information unless explicitly allowed by policy.

## Configuration Overview
### Testing
- Require shell script unit tests (e.g., with `bats`), integration tests for MCP protocol compliance, and validation using the `rpi-scripts/test_mcp_local.sh` test harness for any protocol-relevant logic.
- Provide Copilot context via repo-level `.copilot-instructions` that emphasize test-driven scaffolding.
- Enforce coverage thresholds through CI (≥90% for critical services, ≥75% for auxiliary packages).

### Linting and Code Style
- Adopt language-specific linters (e.g., `ruff`/`flake8` for Python, `eslint` for TypeScript) with project-configured rule sets.
- Mandate formatting via `black`, `isort`, or `prettier` before commit to avoid noisy diffs.
- Encourage Copilot suggestions that respect docstrings, typing hints, and single-responsibility functions.

### Async Patterns
- Use Bash background jobs (`&`), `wait`, and process management (`jobs`, `kill`) for asynchronous or parallel operations.
- Require explicit timeout handling (e.g., with `timeout` or background monitoring), and ensure that background jobs are tracked and cleaned up to avoid orphaned processes.
- All asynchronous logic should be surfaced through central runner scripts to maintain clear process boundaries and structured job control.

### Security Defaults
- Enforce parameter validation, signature verification, and safe deserialization.
- Require Copilot to recommend dependency pinning and supply chain verification (hash checking, `pip-audit` fixes).
- For infra code, demand zero-trust defaults (service meshes, role-based access control) and automatic secret rotation hooks.

### Logging and Observability
- Standardize on structured logging using the Bash functions `parrot_log()`, `parrot_info()`, and `parrot_error()` defined in `rpi-scripts/common_config.sh`. All logs are written to `./logs/parrot.log`.
- Encourage emission of metrics and traces via OpenTelemetry exporters configured in `observability.yaml`.
- Prevent Copilot from generating noisy or personally identifiable logs; adhere to redact-before-log utilities.

### CI/CD Integration
- Align Copilot scaffolding with declarative pipeline definitions. Every merge triggers lint, test, and deployment simulations.
- Enforce manual approvals for production releases, even when Copilot suggests automation.
- Integrate feature flags and canary release scripts to enable safe rollouts.

### Version Control Practices
- Use short-lived feature branches with descriptive names (`feature/strategy-drawdown-guard`).
- Require conventional commit messages to support semantic release.
- Reject large, mixed-purpose commits; Copilot suggestions should target the smallest viable change.

## Custom Instruction Behavior
### High-Level Rules
1. Never commit unreviewed secrets or proprietary strategies.
2. Always scaffold tests alongside new modules.
3. Prefer existing utility abstractions over inventing new frameworks.
4. Escalate to human review when uncertainty about regulatory compliance arises.

### Conceptual YAML Configuration
```yaml
copilot:
  persona: "Disciplined pair programmer for Trading Bot Swarm"
  prohibited_behaviors:
    - "Suggesting code that bypasses authentication or risk controls"
    - "Generating sample credentials or hard-coded secrets"
  code_style:
    python:
      formatter: black
      linter: ruff
      typing: mandatory
    typescript:
      formatter: prettier
      linter: eslint
  testing:
    enforce: true
    strategy: "Write unit + integration tests before finalizing implementation"
  review_requirements:
    - "Flag pull requests without tests for new functionality"

codex:
  persona: "Automation orchestrator adhering to Trading Bot Swarm guardrails"
  rules:
    - "Prioritize deterministic code snippets"
    - "Reference existing modules before introducing new ones"
  output:
    format: markdown
    include:
      - "Rationale for chosen approach"
      - "Testing commands"
  ignore_changes:
    - "Documentation-only modifications when suggesting tests"
```

### Emphasis on Quality Gates
- Copilot and Codex instructions must reiterate that every code change includes corresponding tests and linters.
- Documentation-only pull requests are exempt from automated test scaffolding but must still pass link checkers if applicable.

## GitHub Workflow: Lint and Test Automation
Trigger the workflow on pull requests targeting `main` and any push to release branches:
```yaml
name: ci-quality-gate

on:
  pull_request:
    branches: [main]
    paths-ignore:
      - "**/*.md"
      - "docs/**"
  push:
    branches:
      - "release/*"

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
      - name: Lint shell scripts with ShellCheck
        run: |
          shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh

      - name: Check shell script formatting with shfmt
        run: |
          shfmt -d cli.sh scripts/*.sh rpi-scripts/*.sh

      - name: Run MCP server Bash test harness
        run: |
          chmod +x rpi-scripts/test_mcp_local.sh
          ./rpi-scripts/test_mcp_local.sh
```

## Semantic Release and Version Tagging
Implement automated semantic versioning with manual approvals for production:
```yaml
name: release

on:
  workflow_dispatch:
  push:
    branches: [main]
    paths-ignore:
      - "**/*.md"

jobs:
  semantic-release:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: Install release tooling
        run: npm install -g semantic-release @semantic-release/changelog @semantic-release/git
      - name: Run semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
        run: semantic-release
```
- Enforce conventional commits to drive automatic version bumps.
- Publish changelog entries and git tags via semantic release while requiring human approval before deploying tagged builds to production brokers.

## Security and Dependency Scanning
Augment CI with nightly security scans:
```yaml
name: security-scan

on:
  schedule:
    - cron: "0 2 * * *"
  workflow_dispatch:

jobs:
  dependency:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Dependency review
        uses: actions/dependency-review-action@v4

  sast:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install tooling
        run: pip install bandit pip-audit
      - name: Static analysis
        run: bandit -r trading_bot_swarm
      - name: Dependency audit
        run: pip-audit
```
- Fail the build for high or critical CVEs; auto-create issues with remediation notes.
- Integrate SARIF uploads to GitHub Security tab to centralize findings.

## Contributor Workflow Guidelines
1. **Proposal:** Open an issue describing the change, associated trading impact, and testing plan.
2. **Branching:** Create a feature branch with conventional naming.
3. **Implementation:** Use Copilot suggestions as a baseline, then refactor to meet standards.
4. **Validation:** Run all linting, unit tests, integration tests, and backtests locally before opening a pull request.
5. **Review Criteria:** Reviewers confirm test evidence, code readability, security posture, and adherence to async and logging conventions. Any AI-generated snippet must show human verification.
6. **Merge:** Require at least two approvals, successful CI pipelines, and green security scans.

## Troubleshooting and Optimization Tips
- **Excessive Copilot noise:** Narrow the prompt context or disable inline completions for complex strategy files; rely on chat-based suggestions for better control.
- **Failed tests due to async race conditions:** Enable `pytest-asyncio` and add deterministic fixtures with simulated exchange feeds.
- **Lint disagreements:** Align local and CI tool versions via `requirements-dev.txt` lockfiles.
- **SARIF overload:** Scope reports by rule severity and leverage baseline files to mute acknowledged technical debt.
- **Slow CI:** Cache dependencies (`actions/cache`) and parallelize backtests with matrix strategies.

## Maintenance Schedule
- **Quarterly review:** Audit Copilot and Codex instruction sets to reflect new architectural patterns, regulations, or exchange integrations.
- **Monthly tooling sync:** Update lint, test, and security tool versions; rotate tokens used in CI.
- **Post-incident update:** Revise guidelines immediately after any production incident linked to automation or AI-assisted code.

## Commitment to Excellence
By standardizing Copilot and Codex behavior, the Trading Bot Swarm community reinforces high-quality, safe, and performant automation. These practices help every contributor deliver resilient trading services that inspire trust and drive long-term ecosystem success.
