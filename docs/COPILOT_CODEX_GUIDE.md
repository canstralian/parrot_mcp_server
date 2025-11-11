# GitHub Copilot & Codex Configuration Guide for the Trading Bot Swarm

## Purpose and Scope
- **Objective**: Establish a single source of truth for configuring GitHub Copilot and Codex so that every contributor receives consistent guidance, adheres to security defaults, and maintains high-quality automation for the Trading Bot Swarm.
- **Applicability**: All contributors, maintainers, and automation bots operating in this repository or derivative services.
- **Pair-programming expectation**: Treat Copilot/Codex as a disciplined collaborator. They must follow the same standards as human contributors—tests must pass, security guardrails stay enabled, and code review norms are respected.

## Configuration Overview
1. **Testing Philosophy**
   - Run unit, integration, and simulation tests relevant to the modified modules.
   - Prioritize determinism; prefer hermetic test fixtures for market replay scenarios.
   - Never skip failing tests; diagnose flakiness before merging.
2. **Linting & Static Analysis**
   - Enforce `shellcheck` and `shfmt` for all Bash scripts in `rpi-scripts/` and `scripts/`.
   - Prevent Copilot/Codex from suggesting code that suppresses linters (e.g., `# shellcheck disable=SC...`) unless explicitly justified in the PR description.
3. **Code Style**
   - Prefer functional purity where possible; isolate side effects in adapters.
   - Async paths must use `asyncio` primitives with explicit timeouts; propagate cancellation.
   - Require type annotations on public functions and protocol boundaries.
4. **Security Defaults**
   - Avoid storing secrets in code snippets; reference secrets via environment variables or secret managers.
   - Enforce least-privilege IAM for any automation tokens referenced in examples.
   - Use parameterized queries for SQL, and verify TLS by default for HTTP clients.
5. **Logging & Observability**
   - Use structured logging (`structlog`/`logging` with JSON formatter) with correlation IDs per request.
   - Emit metrics via OpenTelemetry exporters; tag automated trades with strategy identifiers.
   - Collect traces for long-running orchestration flows; add spans for external API calls.
6. **CI/CD Integration**
   - All Copilot/Codex-generated patches must trigger the same CI gates as human contributions.
   - Require green status checks before merge; block merges on failed security scans.
7. **Version Control Discipline**
   - Keep commits atomic; each commit should address a single intent and include passing tests.
   - Write conventional commit messages for release automation (`feat:`, `fix:`, `chore:` etc.).
   - Restrict force pushes to release maintainers; bots must push to dedicated branches.

## Custom Instruction Behavior
### Example Rules for Copilot & Codex
- Never accept incomplete code; if unsure, request clarification.
- Suggest test cases alongside implementation changes.
- Highlight security-sensitive operations for reviewer attention.
- Decline to auto-generate secrets or embed API keys.

### Conceptual YAML Custom Instructions
```yaml
copilot:
  persona: "Disciplined quantitative engineer"
  behavior:
    - "Act as a pair programmer that proposes complete, secure diffs."
    - "Refuse to generate or commit secrets."
    - "Recommend tests (unit/integration) for each change."
    - "Honor repository lint, type-check, and format rules."
    - "Respect async best practices: await all tasks, propagate cancellations, set timeouts."
  prompts:
    testing: "Have you added or updated tests?"
    security: "Are all credentials sourced from secrets management?"
    observability: "Do logs and metrics capture trading context?"

codex:
  persona: "Automation gatekeeper"
  behavior:
    - "Validate Copilot outputs against coding standards."
    - "Block merges if lint/tests/security scans are failing."
    - "Ignore documentation-only diffs when running test suites, but still lint markdown."
    - "Flag async code lacking timeouts or exception handling."
  pipelines:
    - name: "quality_gates"
      runs: ["lint", "test", "type-check"]
      ignore:
        paths: ["**/*.md", "docs/**"]
        when: "no code files changed"
```

### Emphasis on Tests & Linters
- Copilot/Codex must always recommend running tests and linters after code changes.
- Documentation-only changes should skip runtime tests but still perform markdown linting and link checks.

## GitHub Workflow: Lint & Test Automation
Trigger: push or pull request to protected branches (`main`, `release/*`), excluding markdown-only changes.

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
      - uses: actions/setup-python@v4
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: pip install -r requirements.txt
      - name: Static analysis
        run: |
          ruff check .
          mypy src
      - name: Formatting check
        run: |
          black --check src tests
      - name: Unit tests
        run: pytest --maxfail=1 --disable-warnings
      - name: Integration tests (conditional)
        if: contains(github.event.pull_request.labels.*.name, 'run-integration')
        run: pytest tests/integration --maxfail=1
```

## Best Practice Workflows
### Semantic Release & Version Tagging
```yaml
name: release
on:
  push:
    branches: [main]

jobs:
  semantic-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: Install dependencies
        run: npm ci
      - name: Semantic release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
        run: npx semantic-release
```

### Security & Dependency Scanning
```yaml
name: security-scans
on:
  schedule:
    - cron: "0 3 * * 1"  # Every Monday 03:00 UTC
  workflow_dispatch: {}

jobs:
  dependencies:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Dependency audit
        run: pip-audit

  codeql:
    uses: github/codeql-action/codeql@v2
    with:
      languages: python
      queries: security-extended

  secret-scanning:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: gitleaks/gitleaks-action@v2
```

## Contributor Guidelines
1. **Proposal Stage**
   - Open a GitHub issue describing the trading strategy or infrastructure change.
   - Provide risk assessment, telemetry impact, and validation plan.
2. **Review Criteria**
   - Completeness: implementation + tests + documentation updates where necessary.
   - Safety: adherence to security defaults, dependency hygiene, and logging policy.
   - Performance: demonstrate latency/throughput impact for trading-critical paths.
3. **Validation Process**
   - Run `quality-gate` workflow locally or via GitHub Actions before requesting review.
   - Attach evidence of backtests/simulations for strategy alterations.
   - Obtain approvals from domain owners (strategy, infra, security) prior to merge.

## Troubleshooting & Optimization Tips
- **Copilot suggestions are off-topic**: regenerate prompts with tighter context; reference the YAML custom instructions.
- **Codex rejects merge despite passing tests**: ensure lint/static analysis logs are clean; check for skipped scans.
- **Flaky async tests**: inject `asyncio.TimeoutError` guards and enable deterministic seeds for market data.
- **Security scans flag secrets**: rotate credentials, revoke leaked tokens, and document remediation steps.
- **Performance regressions**: use profiling hooks (`py-spy`, `cProfile`) and compare with baseline traces.

## Maintenance Schedule
- Review this guide quarterly during the architecture guild meeting.
- Update after major tooling upgrades (new Python version, CI runner changes, or security policy revisions).
- Track revisions via semantic versioning embedded in the document front matter (future enhancement).

## Closing Note
Standardizing excellence across Copilot, Codex, and human contributors strengthens the reliability, performance, and safety of the Trading Bot Swarm. Revisit these practices regularly to keep automation trustworthy and resilient.
