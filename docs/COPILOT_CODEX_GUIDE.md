# Trading Bot Swarm Copilot & Codex Configuration Guide

## Purpose and Scope
- Define how GitHub Copilot and Codex operate as disciplined pair programmers within the Trading Bot Swarm ecosystem.
- Standardize behaviors that reinforce safety, reliability, and performance in automated trading workflows.
- Provide actionable configuration, automation, and governance patterns for contributors, maintainers, and CI/CD infrastructure.

## Behavioral Charter for AI Pair Programmers
1. **Copilot Role**: Context-aware assistant that suggests code conforming to project rules, never committing directly, and always deferring to human review.
2. **Codex Role**: Automation engine for scripted refactors, migration scaffolding, and bulk updates; operates only within predefined guardrails.
3. **Mandatory Practices**:
   - Generate suggestions that preserve deterministic builds, deterministic tests, and security defaults.
   - Surface risks (e.g., missing input validation, blocking I/O in async flows) inline with generated code comments.
   - Default to least privilege for secrets, tokens, and environment variables.
   - Avoid suggesting dependency downgrades or unvetted packages; prioritize internal utilities.
   - Always prompt humans to run tests and linters before accepting suggestions.

## Configuration Overview
### Editor Extensions
- Enable GitHub Copilot in IDEs (VS Code, PyCharm) with organization policy enforcement.
- Set Copilot chat instructions to reference this guide when generating code or performing reviews.
- Configure Copilot to respect `.editorconfig`, `.flake8`, `pyproject.toml`, and formatter settings.

### Testing & Linting
- Default test runner: `pytest -m "not slow"` for quick cycles; full suite nightly.
- Lint stack: `ruff check`, `mypy` for typing, `black` for formatting.
- Copilot/Codex suggestions must include companion test updates or explain why tests are unaffected.

### Code Style and Async Patterns
- Follow project style defined in `pyproject.toml` (88-char lines, type hints required).
- Async services must use `asyncio`, `anyio`, or FastAPI patterns with cancellation handling.
- Prefer non-blocking I/O; wrap sync calls in executors when unavoidable.

### Security Defaults
- Enforce parameterized queries, sanitized logging, and input validation through Pydantic models.
- Store secrets in Vault/Parameter Store; never hard-code credentials.
- Copilot suggestions should highlight security-sensitive sections (crypto, auth) for manual review.

### Logging & Observability
- Use structured logging via `structlog` or project logging adapters.
- Emit trace IDs and correlation metadata for cross-service observability.
- Metrics collection via OpenTelemetry exporters; Copilot must align instrumentation with existing metrics names.

### CI/CD Integration
- All branches trigger lint/test workflows; protected branches require passing checks and review.
- Deployment pipelines require signed tags and changelog entries.
- Automations must respect feature flags and staged rollout toggles.

### Version Control Discipline
- Enforce conventional commit messages; Codex automations must generate semantic messages (e.g., `feat:`, `fix:`).
- Always rebase on latest `main` before PR; Copilot reminders should reflect this.
- Binary artifacts remain untracked; SARIF reports stored as CI artifacts when needed.

## Custom Instruction Profiles

### Example Rules
- **Rule 1**: "Before proposing code, confirm the relevant module has unit tests and note which tests to run."
- **Rule 2**: "For async handlers, ensure awaited calls have timeout protections."
- **Rule 3**: "Flag any untyped public interfaces as needing type hints."

### Conceptual YAML for Copilot
```yaml
copilot:
  persona: "Trading Bot Swarm guardian"
  priorities:
    - enforce_security_defaults
    - advocate_for_tests
    - preserve_async_integrity
  allowed_actions:
    - suggest_code_with_context
    - draft_review_comments
    - outline_test_plans
  forbidden_actions:
    - auto_commit
    - introduce_unreviewed_dependencies
  reminders:
    - "Run ruff, mypy, and pytest before finalizing changes."
    - "Skip documentation-only edits when running heavy test suites."
```

### Conceptual YAML for Codex
```yaml
codex:
  persona: "Automated refactor specialist"
  triggers:
    - dependency_updates
    - schema_migrations
    - bulk_lint_fixes
  safeguards:
    - require_issue_link: true
    - require_review_signoff: true
    - limit_scope: "src/, tests/"
  workflow:
    - run: "ruff check"
    - run: "mypy"
    - run: "pytest"
  skip_patterns:
    - "docs/**"
    - "*.md"
```

## Workflow Automation Examples

### Lint & Test Quality Gate
```yaml
name: lint-and-test

on:
  pull_request:
    branches: ["main", "release/*"]
  push:
    branches: ["feature/**"]

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-dev.txt
      - name: Lint
        run: |
          ruff check
          black --check .
      - name: Type check
        run: mypy
      - name: Tests
        run: pytest -m "not slow"
      - name: Upload SARIF (optional)
        if: success()
        run: |
          env-sync-check check \
            --example .env.example \
            --schema parrot_mcp_server.core.config:Settings \
            --report sarif --out env-sync-check.sarif.json
        shell: bash
      - uses: github/codeql-action/upload-sarif@v3
        if: success()
        with:
          sarif_file: env-sync-check.sarif.json
```

### Semantic Release & Tagging
```yaml
name: semantic-release

on:
  push:
    branches: ["main"]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: Install release tooling
        run: npm install -g semantic-release @semantic-release/git @semantic-release/changelog
      - name: Run semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npx semantic-release
```

### Security & Dependency Scanning
```yaml
name: security-scan

on:
  schedule:
    - cron: "0 3 * * 1"  # Mondays 03:00 UTC
  workflow_dispatch:

jobs:
  dependencies:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Python dependency audit
        run: pip install pip-audit && pip-audit
      - name: OSV scanner
        uses: google/osv-scanner-action@v1
        with:
          path: .
  codeql:
    uses: github/codeql-action/analyze@v3
    with:
      category: "/language:python"
```

## Contributor Workflow Guidelines
1. **Proposing Changes**
   - Open an issue describing scope, risk, and testing strategy.
   - Draft PR with conventional commit title and checklist confirming lint/test runs.
   - Attach SARIF reports when environmental drift checks are relevant.

2. **Review Criteria**
   - Code adheres to style, typing, and async guidelines.
   - Security posture maintained: secrets management, validation, logging hygiene.
   - Tests cover new/changed behavior with deterministic results.
   - CI pipelines green; SARIF artifacts free of warnings or noted with mitigation.

3. **Validation Process**
   - Author runs `ruff check`, `black --check`, `mypy`, and `pytest` locally.
   - Reviewer re-runs targeted tests for high-risk modules.
   - Merge only after automated checks and human review confirm compliance.

## Troubleshooting & Optimization
- **Copilot Suggestions Off-Spec**: Reset custom instructions, clear IDE cache, ensure `.editorconfig` synced.
- **Async Deadlocks**: Inspect for missing `await` or blocking calls; use `asyncio.TimeoutError` guards.
- **Flaky Tests**: Quarantine with `@pytest.mark.flaky`, log seed values, review external service mocks.
- **SARIF Upload Fails**: Validate JSON schema with `sarif-tools validate` and verify GitHub token scopes.
- **Performance Regression**: Enable profiling (`py-spy`, `cProfile`), capture metrics via observability stack, compare baselines.

## Maintenance Schedule
- **Monthly**: Review tooling versions (Copilot, Codex, linters), update YAML examples.
- **Quarterly**: Audit security defaults, dependency policies, and CI workflows.
- **Release Cycle**: Align guide with latest semantic release configuration and observability standards.

## Commitment to Excellence
Standardizing these practices elevates the reliability, performance, and safety of the Trading Bot Swarm ecosystem, ensuring AI-assisted development remains disciplined and trustworthy.
