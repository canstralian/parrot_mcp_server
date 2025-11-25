# GitHub Copilot & Codex Configuration Guide for the Trading Bot Swarm

## Purpose and Scope
- **Objective**: Provide a single, authoritative playbook for configuring GitHub Copilot and Codex so contributors and automation share the same standards across the Trading Bot Swarm ecosystem.
- **Applicability**: All maintainers, contributors, release engineers, CI/CD pipelines, and service accounts interacting with this repository or downstream forks.
- **Pair-programming expectation**: Treat Copilot/Codex as disciplined pair programmers with zero tolerance for partial solutions; suggestions must uphold security defaults, code quality, and observability requirements before they are accepted.
- **Out-of-scope**: Cloud infrastructure rollout and environment provisioning are documented separately; this guide focuses on developer experience, automation behavior, and CI policy.

## Configuration Overview
1. **Testing Philosophy**
   - Run unit, integration, contract, and simulation tests relevant to touched modules before merging.
   - Favor deterministic fixtures for protocol message flows; record/playback external calls where possible.
   - Do not skip failing or flaky tests. Investigate and deflake before merge.
   - Capture coverage for critical trading strategies and MCP protocol edges; block on meaningful coverage regressions.
2. **Linting & Static Analysis**
   - Enforce `shellcheck` and `shfmt` for Bash in `rpi-scripts/` and `scripts/`.
   - Use repository linters (e.g., `ruff`, `mypy`, `eslint`) where configured; do not suppress warnings without justification in the PR description.
   - Prefer pre-commit hooks to keep formatting consistent before CI; pin tool versions in CI to avoid drift.
3. **Code Style & Async Patterns**
   - Keep side effects isolated in adapters; keep core logic functional and pure when practical.
   - All public functions require type annotations; treat protocol boundaries as typed contracts.
   - Async code must await tasks, propagate cancellations, apply explicit timeouts to outbound calls, and guard against unbounded concurrency.
   - Prefer structured error handling over blanket exception catches; surface actionable messages with context IDs and remediation guidance.
4. **Security Defaults**
   - Never embed secrets or tokens in code or tests; load from environment variables or secret managers.
   - Apply least-privilege IAM for automation tokens; scope PATs to required repos and permissions only.
   - Enforce TLS verification by default; use parameterized queries for data stores; sign and verify artifacts in CI.
   - Redact sensitive fields in logs and traces; ensure rotated credentials invalidate prior tokens.
5. **Logging & Observability**
   - Emit structured logs (JSON) with correlation IDs per request and per trade execution.
   - Instrument spans for external API calls and long-running orchestration; export traces via OpenTelemetry.
   - Tag metrics with strategy identifiers and MCP component names; monitor latency/throughput regressions and surface SLO dashboards.
   - Include diagnostic context (version tag, commit SHA, environment) in logs and traces to simplify incident response.
6. **CI/CD Integration**
   - Copilot/Codex-generated diffs must trigger the same CI gates as human changes.
   - Block merges on failed quality gates, security scans, or missing approvals; require green checks before tagging releases.
   - Keep pipelines hermetic: pin tool versions, vendor deterministic dependencies when possible, and avoid network access where feasible during tests.
7. **Version Control Discipline**
   - Use conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, etc.) to support semantic release.
   - Keep commits atomic and scoped to one intent; include tests relevant to that intent and note skipped cases explicitly.
   - Avoid force pushes on protected branches; automation uses dedicated branches with PRs and rebase/merge strategies approved by maintainers.

## Custom Instruction Behavior
### Example Rules for Copilot & Codex
- Never provide incomplete code; if context is insufficient, ask for clarification or suggest guarded placeholders with TODOs.
- Recommend or auto-generate tests alongside implementation changes.
- Highlight security-sensitive operations (credentials, key management, signing) for reviewer attention.
- Refuse to generate secrets, API keys, or hard-coded credentials.
- Prefer safe defaults for timeouts, retries, circuit-breaking, and cancellation in async workflows.
- Encourage observability updates (logs, metrics, traces) when touching orchestration, scheduling, or external API calls.

### Conceptual YAML Custom Instructions
```yaml
copilot:
  persona: "System automation engineer for the Trading Bot Swarm"
  behavior:
    - "Act as a pair programmer that proposes complete, secure diffs with tests."
    - "Refuse to generate or commit secrets."
    - "Recommend unit/integration tests and observability updates for each change."
    - "Honor repository lint, type-check, and format rules."
    - "Respect async best practices: await tasks, propagate cancellations, set timeouts, and avoid unbounded concurrency."
    - "Document edge cases and rollback considerations for automation flows."
  prompts:
    testing: "Have you added or updated tests for trading strategies, protocols, and scripts?"
    security: "Are credentials sourced from secrets management with least privilege?"
    observability: "Do logs, metrics, and traces capture MCP server automation events?"

codex:
  persona: "Automation gatekeeper"
  behavior:
    - "Validate Copilot outputs against coding standards and security defaults."
    - "Block merges if lint/tests/security scans fail or are missing."
    - "Ignore runtime tests for documentation-only diffs but still run markdown linting/link checks."
    - "Flag async code lacking timeouts, cancellation, or error propagation."
    - "Require structured logs with correlation IDs for new automation paths."
  pipelines:
    - name: "quality_gates"
      runs: ["lint", "test", "type-check", "security-scan"]
      ignore:
        paths: ["**/*.md", "docs/**"]
        when: "no code files changed"
```

### Emphasis on Tests & Linters
- Copilot/Codex must always recommend running tests and linters after code changes.
- Documentation-only changes should skip runtime test suites but must run markdown linting, link checks, and spell checks.

## GitHub Workflow: Lint & Test Automation
Trigger on pushes or pull requests to protected branches (`main`, `release/*`), while ignoring markdown-only changes.

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
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
      - name: Lint shell scripts
        run: |
          shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh
          shfmt -d cli.sh scripts/*.sh rpi-scripts/*.sh
      - name: Lint Python
        run: |
          ruff check .
          mypy .
      - name: Run tests
        run: |
          pytest --maxfail=1 --disable-warnings -q
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
      - name: Use Node for semantic-release
        uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: Install release tooling
        run: |
          npm ci
      - name: Run semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
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
      - name: Python dependency audit
        run: pip install pip-audit && pip-audit --desc --strict
      - name: Node dependency audit
        run: npm audit --audit-level=high

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

### CI/CD Guardrails for Infrastructure Changes
```yaml
name: infra-changes
on:
  pull_request:
    branches: [main, "release/*"]
    paths:
      - "infra/**"
      - "deploy/**"

jobs:
  plan-and-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate Terraform
        run: terraform fmt -check && terraform validate
      - name: Terraform plan
        env:
          TF_CLOUD_TOKEN: ${{ secrets.TF_CLOUD_TOKEN }}
        run: terraform plan -no-color
      - name: Policy checks
        run: |
          opa eval --fail-defined -i policy/inputs.json -d policy --data policy
```

## Contributor Guidelines
1. **Proposal Stage**
   - Open an issue describing the automation feature, MCP protocol update, or infrastructure change along with risk/impact analysis.
   - Include validation and rollback plans plus observability hooks you intend to add.
   - Note whether changes affect runtime behavior, CI policy, or documentation-only areas.
2. **Review Criteria**
   - Completeness: implementation, tests, and documentation updates where required.
   - Safety: adherence to security defaults, dependency hygiene, and logging/metrics policies.
   - Performance: demonstrate latency/throughput impact for automation-critical paths with reproducible benchmarks.
   - Release readiness: commits follow conventional format, CI pipelines are green, and semantic-release will classify correctly.
3. **Validation Process**
   - Run `quality-gate` locally or via GitHub Actions before requesting review.
   - Provide evidence of tests/simulations for protocol or strategy changes, including failure cases and rollback drills.
   - Obtain approvals from domain owners (automation, infra, security) prior to merge.
   - Ensure semantic-release scope and commit types match intent; verify generated changelog entries in dry runs.

## Troubleshooting & Optimization Tips
- **Copilot suggestions are off-topic**: regenerate prompts with tighter context; reference the YAML custom instructions.
- **Codex blocks merge despite passing tests**: ensure lint/static/security logs are clean; confirm markdown-only changes are excluded from runtime tests.
- **Flaky shell tests**: apply `timeout` guards, use deterministic fixtures, and prefer hermetic mocks for external services.
- **Security scans flag secrets**: rotate credentials, revoke leaked tokens, and document remediation steps.
- **Performance regressions**: benchmark with `time`, `strace`, and tracing; compare against baseline metrics.
- **Semantic-release errors**: verify branch protection, token scopes, and that commit messages follow conventional format.
- **CI rate limits or cache misses**: pin action versions, enable dependency caching, and stagger scheduled workflows.

## Maintenance Schedule
- Review this guide quarterly and after major tooling upgrades (new Python/Node versions, CI runner updates, security policy changes).
- Track revisions via semantic versioning embedded in the document front matter (planned enhancement).
- Archive superseded guidance but keep changelog entries for traceability.
- Align updates with MCP protocol revisions and infrastructure drift remediation cycles.

## Closing Note
Standardizing excellence across Copilot, Codex, and human contributors strengthens the reliability, performance, and safety of the Trading Bot Swarm. Revisit these practices regularly to keep automation trustworthy and resilient.
