# GitHub Copilot & Codex Configuration Guide for the Trading Bot Swarm

## Purpose & Scope
This guide standardizes how GitHub Copilot and Codex operate within the Trading Bot Swarm ecosystem. It positions Copilot as a disciplined pair programmer that supports, but never overrides, engineering judgment. The document defines configuration practices, automation workflows, and contributor expectations to ensure consistency, code quality, and secure operations across all services powering the trading platform.

## Behavioral Charter for AI Pair Programmers
- **Copilot as a collaborator:** Copilot proposes code aligned with established architecture, security, and performance principles. Human review is mandatory for every suggestion.
- **Strict boundaries:** Copilot must never commit secrets, bypass lint/test failures, or disable safeguards for convenience. Prefer explicitness over "magic" code.
- **Traceability:** Annotate generated snippets with rationale in PR descriptions when Copilot substantially contributes to a change.
- **Fallback readiness:** Engineers must be able to continue work without Copilot. Tooling configuration must degrade gracefully.

## Configuration Overview
| Domain | Standards |
| --- | --- |
| **Testing** | All non-doc changes require fast unit tests plus targeted integration tests (`pytest`, `pytest-asyncio`). Mandatory coverage thresholds defined per service. |
| **Linting** | Enforce `ruff` for Python, `eslint` + `prettier` for TypeScript, `shellcheck` for shell scripts. Lints run locally and in CI. |
| **Code Style** | Adopt `ruff format`/`black` compatibility for Python, `prettier` defaults for JS/TS, and `EditorConfig` for shared whitespace rules. |
| **Async Patterns** | Prefer `asyncio` with structured concurrency (`anyio.create_task_group`) and cancellation handling. Avoid blocking I/O in async contexts. |
| **Security Defaults** | Enable dependency pinning, enforce `bandit`/`semgrep` for security scanning, and require secrets scanning (`trufflehog`). |
| **Logging & Observability** | Use `structlog` + OpenTelemetry with JSON logs. Correlate traces through `trace_id` propagation. |
| **CI/CD Integration** | GitHub Actions orchestrates lint/test pipelines, semantic releases, and deployments. Each workflow stores artifacts and coverage reports. |
| **Version Control** | Branch protection enforces signed commits, status checks, and linear history. Conventional commit messages drive semantic releases. |

## Custom Instruction Profiles
Define explicit guardrails for Copilot and Codex so their suggestions remain deterministic and compliant.

### Conceptual YAML: Copilot Pair Programmer
```yaml
copilot:
  role: "pair_programmer"
  priorities:
    - uphold_security_controls
    - respect_existing_architecture
    - optimize_for_readability
    - write_testable_code
  prohibited_actions:
    - "suggest disabling linters or tests"
    - "commit secrets or credentials"
    - "modify deployment manifests without approval"
  review_prompts:
    pull_request: |
      Confirm all code changes include tests or a clear justification.
      Highlight any deviations from async or security guidelines.
  documentation_policy: "Provide inline comments only when they clarify non-trivial logic."
```

### Conceptual YAML: Codex Automation Agent
```yaml
codex:
  role: "automation_specialist"
  behaviors:
    orchestrate_ci_cd: true
    enforce_quality_gates: true
    avoid_unreviewed_merges: true
  response_rules:
    - "Run unit tests and linters before proposing merges."
    - "Ignore documentation-only changes for mandatory test execution."
    - "Escalate security warnings to human reviewers."
  output_style:
    summary: "Concise, bullet-based status."
    logs: "Link to workflow runs and artifacts."
```

> **Key Reminder:** Any code change (besides documentation-only updates) must run the relevant tests and lint checks locally and in CI. Documentation-only PRs may skip code checks but still require prose review.

## GitHub Workflow: Lint & Test Automation
```yaml
name: quality-gate

on:
  pull_request:
    branches: ["main", "release/*"]
    paths-ignore:
      - "**/*.md"
      - "docs/**"
  push:
    branches: ["main"]

jobs:
  quality:
    name: Lint & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: pip install -r requirements.txt
      - name: Lint
        run: |
          ruff check .
          ruff format --check .
          pytest --collect-only
      - name: Test
        run: pytest --maxfail=1 --disable-warnings -q
      - name: Upload coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: htmlcov
```

## Semantic Release & Version Tagging Workflow
```yaml
name: semantic-release

on:
  push:
    branches: ["main"]

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      issues: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - name: Run semantic release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
        run: npx semantic-release
      - name: Publish release notes
        if: success()
        run: echo "Release published"
```

## Security & Dependency Scanning Workflow
```yaml
name: security-scan

on:
  schedule:
    - cron: "0 6 * * 1"  # Weekly Monday scan
  workflow_dispatch:

jobs:
  dependencies:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Dependency review
        uses: actions/dependency-review-action@v3
  sast:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Bandit
        run: pip install bandit && bandit -r .
      - name: Run Semgrep
        uses: returntocorp/semgrep-action@v1
        with:
          config: "p/ci"
  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: TruffleHog scan
        uses: trufflesecurity/trufflehog@v3
        with:
          scan: git
```

## Contributor Workflow
1. **Plan & Propose:** Open a GitHub issue describing scope, risks, and validation strategy.
2. **Develop:** Create a feature branch, follow AI instruction profiles, and run `ruff`, `pytest`, and any domain-specific checks.
3. **Document:** Update relevant README, ADRs, or runbooks when behavior changes. Documentation-only changes are exempt from code checks but still need reviewer approval.
4. **Submit PR:** Include test results, coverage summary, and note any Copilot-generated sections. Adhere to conventional commits for titles.
5. **Review Criteria:**
   - Tests cover new logic and pass.
   - Lint/security checks clean.
   - Async patterns respect cancellation and error propagation.
   - Logging/telemetry consistent with observability standards.
   - No secrets or sensitive data present.
6. **Validation:** CI must succeed. For high-risk changes, request manual QA or chaos testing sign-off before merge.

## Troubleshooting & Optimization
- **Copilot suggestions feel off:** Refresh context by summarizing architecture in the file header or referencing relevant modules. Temporarily disable Copilot if it repeats anti-patterns.
- **Flaky tests:** Stabilize by isolating async I/O with `pytest-timeout`, using deterministic seeds, and ensuring cleanup hooks run.
- **Slow pipelines:** Cache dependencies (`actions/cache` for pip/npm) and shard tests with `pytest -n auto` or GitHub matrix strategy.
- **Security scan noise:** Tune Semgrep rulesets and maintain `.semgrepignore`. For TruffleHog false positives, add hashed exceptions with documented approval.

## Maintenance Schedule
- **Quarterly review:** Validate tooling versions, workflow triggers, and coverage thresholds.
- **Monthly check:** Ensure AI instruction YAML mirrors live configuration in Copilot/Codex dashboards.
- **Release alignment:** Update guide after every semantic release to reflect new modules or service boundaries.

## Closing Note
Standardizing excellence is essential to the Trading Bot Swarm's mission. Adhering to this guide strengthens reliability, performance, and safety across the trading ecosystem, ensuring every automated action reflects our highest engineering standards.
