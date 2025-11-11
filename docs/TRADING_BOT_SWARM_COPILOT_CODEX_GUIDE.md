# Trading Bot Swarm – Copilot & Codex Configuration Guide

## Purpose and Scope
This guide establishes a unified configuration for GitHub Copilot and Codex within the Trading Bot Swarm ecosystem. It defines how automated assistance should behave, the guardrails that keep our services secure, and the quality controls that every contributor must respect. Treat Copilot as a disciplined pair programmer that proposes changes aligned with our engineering standards, never as an autonomous decision-maker.

## Configuration Overview
The following principles keep the codebase reliable, observable, and secure:

- **Testing & Verification**: Every code change must have automated tests. Prefer unit tests first, expand to integration and contract tests for components that interact with exchanges, brokers, or messaging layers.
- **Linting & Static Analysis**: Enforce language-specific linters (`ruff`, `eslint`, `golangci-lint`, etc.) with strict error thresholds. Linting runs locally before commits and in CI.
- **Code Style**: Follow formatter defaults (`black`, `prettier`, `gofmt`). Avoid manual tweaks that fight the formatter. Comment intent, not mechanics.
- **Async Patterns**: Use async I/O for exchange clients, websockets, and risk analytics. Never block event loops; delegate CPU-heavy work to worker pools.
- **Security Defaults**: Enable least privilege for API keys, encrypt secrets via GitHub Actions secrets or HashiCorp Vault, and mandate parameter validation on every external input.
- **Logging & Observability**: Emit structured logs (JSON) with correlation IDs. Instrument latency, error rate, and throughput metrics via OpenTelemetry. Surface production dashboards in Grafana.
- **CI/CD Integration**: Every push to `main` comes from a reviewed PR. CI must execute lint, test, security scans, and build artifacts. CD uses progressive rollouts with automatic rollback triggers.
- **Version Control Hygiene**: Maintain small, focused commits. Reference Jira tickets in commit messages and PR descriptions. Never merge directly to `main` without status checks.

## Custom Instruction Behavior for Copilot and Codex
Codex and Copilot must follow consistent guardrails:

1. **Rule Hierarchy**: System > Repository > Team > User instructions.
2. **Testing Obligation**: Always run tests and linters when code changes; skip for documentation-only edits.
3. **Security Awareness**: Reject suggestions that expose secrets, disable security tooling, or bypass access controls.
4. **Review Prep**: Generate PR summaries highlighting risk areas, test coverage, and migration considerations.
5. **Traceability**: Reference relevant modules, feature flags, and runbook links in generated explanations.

### Example Custom Instructions (Conceptual YAML)
```yaml
assistant_profile:
  name: trading-bot-swarm-copilot
  mindset:
    - Act as a vigilant pair programmer.
    - Prefer safe defaults over clever shortcuts.
    - Never fabricate test results or execution logs.
  quality_gates:
    code_changes:
      - run: "make lint"
      - run: "make test"
      - refuse_if_failed: true
    docs_only:
      - note: "tests optional – document why they were skipped"
  security:
    - deny_secret_creation: true
    - enforce_dependency_pinning: true
  review_brief:
    include:
      - summary
      - test_matrix
      - risk_register
```

## Lint and Test Automation Workflow
Trigger continuous quality checks on pull requests and protected branches:

- **Triggers**: `pull_request` on `main`, `develop`, release branches; `push` on `main` for branch protection.
- **Quality Gate Steps**:
  1. Checkout repository.
  2. Set up language runtimes (Python, Node.js, Go).
  3. Install dependencies with caching.
  4. Run linters.
  5. Execute unit and integration tests.
  6. Upload coverage reports and artifacts.

```yaml
name: lint-and-test
on:
  pull_request:
    branches: [main, develop, 'release/**']
  push:
    branches: [main]

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - name: Install dependencies
        run: make install
      - name: Run linters
        run: make lint
      - name: Run tests
        run: make test
      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/
```

## Semantic Release and Version Tagging Workflow
Use semantic commits (`feat:`, `fix:`, `perf:`, etc.) to generate changelogs and tags automatically.

```yaml
name: semantic-release
on:
  workflow_run:
    workflows: ["lint-and-test"]
    types: [completed]
    branches: [main]

jobs:
  release:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

## Security and Dependency Scanning Workflow
Augment quality gates with continuous scanning.

```yaml
name: security-scan
on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:

jobs:
  dependencies:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Dependency review
        uses: github/dependency-review-action@v4
        with:
          fail-on-severity: high
  codeql:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    strategy:
      matrix:
        language: [javascript, python, go]
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
      - uses: github/codeql-action/analyze@v3
```

## Contributor Guidelines
1. **Proposing Changes**: Open a GitHub issue or link to an existing Jira ticket. Provide scope, impact, and rollback plan.
2. **Implementation**: Create feature branches, follow commit conventions, and keep diffs small.
3. **Review Criteria**: Reviewers verify automated test evidence, security posture, logging completeness, and adherence to custom instructions.
4. **Validation**: Before merge, ensure CI pipelines pass, manual smoke tests (if applicable) succeed, and documentation/runbooks are updated.

## Troubleshooting and Optimization
- **Copilot Suggestions Misaligned**: Regenerate with more context or restate the desired behavior in comments.
- **Failing Linters**: Run `make fmt` to auto-format, then lint again. Investigate warnings that persist.
- **Flaky Tests**: Re-run locally with increased logging, isolate external dependencies using mocks or sandbox credentials.
- **Slow CI Jobs**: Enable dependency caching (`actions/cache`) and split large integration suites into parallel jobs.
- **Security Alerts**: Patch vulnerable packages immediately, document mitigations, and notify the incident response channel.

## Maintenance Schedule
- **Monthly**: Review CI workflows, Copilot/Codex instructions, and dependency pins.
- **Quarterly**: Audit security posture, update observability dashboards, and validate semantic release configuration.
- **After Major Releases**: Reassess async architecture assumptions, update risk matrices, and refresh contributor onboarding materials.

## Closing Note
Standardizing excellence safeguards the Trading Bot Swarm ecosystem. Adhering to this guide strengthens reliability, performance, and safety across every automated trading service.
