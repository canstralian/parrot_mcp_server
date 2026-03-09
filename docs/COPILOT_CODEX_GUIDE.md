# GitHub Copilot & Codex Configuration Guide for the Trading Bot Swarm

## Purpose and Scope
- Establish one operational standard for configuring GitHub Copilot and Codex across the Trading Bot Swarm ecosystem.
- Treat Copilot as a pair programmer with strict behavioral rules: complete changes, secure-by-default output, and quality gates before merge.
- Apply this guide to maintainers, contributors, CI bots, and release automation touching this repository and downstream forks.
- Keep cloud provisioning and environment bootstrap out of scope; this document focuses on development workflow, automation policy, and repository quality controls.

## Configuration Overview
1. **Testing requirements**
   - For code changes, run tests tied to touched modules before review.
   - Use repository-native tooling: BATS for shell behavior and protocol script checks (`bats rpi-scripts/tests/*.bats`).
   - Preserve deterministic test fixtures for automation workflows and protocol interactions.
2. **Linting and formatting**
   - Shell scripts must pass `shellcheck` and `shfmt` (`shellcheck rpi-scripts/cli.sh rpi-scripts/scripts/*.sh rpi-scripts/*.sh`, `shfmt -d rpi-scripts/cli.sh rpi-scripts/scripts/*.sh rpi-scripts/*.sh`).
   - Python code should pass configured static checks (for example `ruff`, `mypy`) when those tools are part of the active pipeline.
3. **Code style and async patterns**
   - Keep logic composable and side effects isolated in adapters or orchestration layers.
   - Require explicit timeout and cancellation behavior for async network-bound work.
   - Avoid broad exception swallowing; errors should be typed, contextual, and actionable.
4. **Security defaults**
   - Never generate or store secrets in source control.
   - Use least-privilege credentials for automation tokens and CI identities.
   - Enforce secure IPC and filesystem permissions in deployment docs and scripts.
5. **Logging and observability**
   - Emit structured logs with correlation/message IDs.
   - Capture metrics and traces around MCP tool execution and long-running automations.
   - Include enough context for incident triage without leaking sensitive data.
6. **CI/CD integration**
   - Copilot/Codex-generated changes follow the exact same quality gates as human-authored code.
   - Block merges when lint, tests, or security scans fail.
   - Keep CI definitions reproducible by pinning action/tool versions.
7. **Version control standards**
   - Use conventional commits to support semantic release (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`).
   - Keep commits narrowly scoped and test-backed.
   - Use protected branches and PR-based merge policies.

## Custom Instruction Behavior for Codex and Copilot

### Example Behavioral Rules
- Always propose complete diffs (code + tests when code changes).
- Refuse to generate secrets or insecure credential handling.
- Run and report lint/test outcomes before finalizing implementation changes.
- Ignore runtime test execution for documentation-only diffs, but still run doc quality checks.
- Surface risk notes for concurrency, IPC boundaries, and permission-sensitive operations.

### Conceptual YAML: Full Custom Instructions
```yaml
assistant_policy:
  project: "Trading Bot Swarm"
  defaults:
    pair_programming_mode: strict
    require_complete_solutions: true
    secure_by_default: true

copilot:
  role: "Pair programmer"
  rules:
    - "Return complete patches; do not leave partial snippets as final output."
    - "For code changes, generate or update relevant tests."
    - "Respect repository linting and formatting standards."
    - "Do not produce secrets, hard-coded credentials, or token material."
    - "Use safe async patterns: explicit timeout, cancellation handling, bounded concurrency."

codex:
  role: "Automation reviewer"
  rules:
    - "Validate suggested changes against lint, test, and security gates."
    - "Require quality checks for code changes."
    - "If only docs changed, skip runtime tests and enforce docs checks only."
    - "Flag missing observability updates on automation-critical modifications."

quality_gates:
  code_changes:
    required: ["lint", "format", "tests", "security_scan"]
  docs_only_changes:
    required: ["markdown_lint", "link_check", "spelling_check"]
    skip: ["runtime_tests"]
```

## GitHub Workflow Example: Lint and Test Automation
Use this workflow for pushes and pull requests to `main` and `release/*`, skipping markdown-only paths.

```yaml
name: quality-gate
on:
  push:
    branches: [main, "release/*"]
    paths-ignore: ["**/*.md", "docs/**"]
  pull_request:
    branches: [main, "release/*"]
    paths-ignore: ["**/*.md", "docs/**"]

jobs:
  quality:
    name: Lint and Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install shell tooling
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck shfmt bats

      - name: Lint shell scripts
        run: |
          shellcheck rpi-scripts/cli.sh rpi-scripts/scripts/*.sh rpi-scripts/*.sh
          shfmt -d rpi-scripts/cli.sh rpi-scripts/scripts/*.sh rpi-scripts/*.sh

      - name: Run shell test suite
        run: bats rpi-scripts/tests/*.bats

      - name: Optional Python lint
        run: |
          python -m pip install --upgrade pip
          pip install ruff mypy
          ruff check src
          mypy src
```

## Best Practice Workflows

### Semantic Release and Version Tagging
```yaml
name: semantic-release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - name: Publish release and tags
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npx semantic-release
```

### Security and Dependency Scanning
```yaml
name: security-scans
on:
  schedule:
    - cron: "0 3 * * 1"
  pull_request:
  workflow_dispatch:

jobs:
  dependency-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Python dependency audit
        run: |
          python -m pip install --upgrade pip pip-audit
          pip-audit --strict

  secrets-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: gitleaks/gitleaks-action@v2

  codeql:
    permissions:
      actions: read
      contents: read
      security-events: write
    uses: github/codeql-action/.github/workflows/codeql.yml@v3
    with:
      languages: "python"
```

## Contributor Guidelines
1. **Propose changes**
   - Describe intent, scope, and risk in the issue/PR.
   - Include testing strategy, rollback notes, and security considerations.
2. **Review criteria**
   - Completeness (implementation + tests + docs as needed).
   - Reliability and performance impact for automation paths.
   - Security posture (least privilege, no secret leakage, safe defaults).
3. **Validation process**
   - Run linting and tests locally when possible.
   - Attach CI evidence in pull request discussion.
   - Ensure commit messages support release automation.

## Troubleshooting and Optimization Tips
- Tighten prompts when Copilot drifts from repository conventions.
- If Codex blocks a PR, inspect failing quality gates first (lint/test/security).
- Deflake shell tests with deterministic fixtures and bounded retries.
- For release failures, validate commit format and semantic-release token scopes.
- For performance regressions, compare before/after run-time metrics and logs.

## Maintenance Schedule
- Review and refresh this guide quarterly.
- Update immediately after major toolchain or policy changes.
- Keep workflow snippets aligned with real CI definitions and repository standards.

## Closing Note
The goal is to standardize excellence across Copilot, Codex, and human contributors, strengthening the reliability, performance, and safety of the trading ecosystem.
