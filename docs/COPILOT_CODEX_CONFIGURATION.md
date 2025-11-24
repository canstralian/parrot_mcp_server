# Trading Bot Swarm Copilot & Codex Configuration Guide

## Purpose and Scope
This guide defines the standards for configuring GitHub Copilot and Codex within the Trading Bot Swarm ecosystem. It ensures every contributor treats Copilot as a disciplined pair programmer with explicit behavioral rules. The document covers:

- Configuration principles for AI-assisted development in Trading Bot Swarm
- Workflow integrations spanning local development, CI/CD, and production readiness
- Enforcement of consistency, code quality, and secure automation practices across teams

The guide applies to all repositories under the Trading Bot Swarm organization and complements existing engineering handbooks. Its overarching objective is to standardize excellence while maintaining the reliability, performance, and safety of our trading infrastructure.

## Configuration Overview

### Behavioral Guardrails for AI Assistants
- Copilot acts strictly as a suggestive partner; engineers must review and adapt all generated code.
- AI suggestions must align with Trading Bot Swarm security policies, safe defaults, and coding conventions.
- Disable Copilot inline acceptance for sensitive files (e.g., secrets management) unless peer reviewed.

### Testing and Linting
- All code changes must include automated unit tests or integration tests as appropriate.
- Run `pytest` (or repository-specific test suites) locally before pushing.
- Execute linters (`ruff`, `black`, `mypy`, or language-specific equivalents) and ensure zero warnings in critical paths.

### Code Style and Patterns
- Adhere to the project’s formatter (e.g., `black` for Python, `prettier` for TypeScript).
- Prefer async/await where IO-bound operations are involved; avoid blocking calls in event loops.
- Enforce dependency injection for services and avoid global state.

### Security Defaults
- Never store secrets in source control; use environment variables or secret management systems.
- Validate all external inputs, especially API payloads and user-supplied data.
- Enable TLS verification for external requests and enforce least privilege for credentials.

### Logging and Observability
- Use structured logging (`logging` with JSON handlers, OpenTelemetry, etc.).
- Include correlation IDs and trace context in distributed components.
- Capture metrics (latency, error rates) and export to the central observability stack.

### CI/CD Integration
- Configuration validation (such as `config_validator.py`) must run before application bootstrap and within CI pipelines.
- Enforce quality gates: lint, test, type-check, security scan, and documentation link validation (when applicable).
- Block merges if any quality gate fails.

### Version Control Practices
- Use feature branches with descriptive names (e.g., `feat/market-data-stream`).
- Commit messages follow Conventional Commits: `type(scope): summary`.
- Rebase interactively to maintain clean history before merging to `main`.

## Custom Instruction Behavior for Copilot and Codex

### Conceptual Guidance
Copilot and Codex should prioritize:
- Compliance with Trading Bot Swarm style guides and security policies.
- Generating tests alongside new code, highlighting edge cases and failure modes.
- Suggesting refactors that maintain backward compatibility and performance.

They must avoid:
- Introducing undocumented dependencies or altering deployment manifests without prompts.
- Generating code that bypasses existing validation, authentication, or rate-limiting layers.
- Redundant documentation updates when code behavior is unchanged.

### Example Rules (Narrative)
1. Always propose unit tests when creating new functions or modules.
2. Recommend running `pytest`, `ruff`, and `mypy` before submitting PRs.
3. Flag missing logging, error handling, or async context management in suggestions.
4. Ignore documentation-only changes when determining whether tests need to run.
5. Escalate security-sensitive operations to manual review.

### Conceptual YAML Configuration
```yaml
ai_assistant:
  role: "Disciplined pair programmer for Trading Bot Swarm"
  behavior:
    must:
      - "Adhere to project-specific linting, formatting, and typing rules"
      - "Produce secure-by-default code with explicit validation and error handling"
      - "Generate test cases and suggest coverage improvements"
      - "Reference internal documentation and existing modules before introducing new ones"
    avoid:
      - "Autocompleting secrets or credentials"
      - "Modifying deployment pipelines without explicit human approval"
      - "Suggesting code that skips logging or observability hooks"
    reminders:
      - "Run pytest, ruff, and mypy for code changes"
      - "Skip test execution for documentation-only updates"
      - "Flag risky async patterns or blocking IO"
  output_style:
    - "Conform to black formatting for Python"
    - "Include docstrings and type hints"
    - "Use descriptive variable names aligned with domain vocabulary"
```

## GitHub Workflow: Lint and Test Automation

### Trigger Conditions
- `push` events on `main`, `release/*`, and `feature/*` branches.
- `pull_request` events targeting `main` and `release/*`.
- Workflow skips automatically for documentation-only changes (`docs/**`, `README.md`).

### Quality Gate Job Steps
```yaml
name: Quality Gate

on:
  push:
    branches: ["main", "release/*", "feature/*"]
  pull_request:
    branches: ["main", "release/*"]
  paths-ignore:
    - "docs/**"
    - "README.md"

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-dev.txt

      - name: Run linters
        run: |
          ruff check .
          black --check .
          mypy .

      - name: Run tests
        run: pytest --maxfail=1 --disable-warnings -q

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: htmlcov
```

## Best Practice Workflows

### Semantic Release and Version Tagging
```yaml
name: Semantic Release

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
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Security and Dependency Scanning
```yaml
name: Security Scan

on:
  schedule:
    - cron: "0 3 * * 1"  # Weekly on Mondays
  workflow_dispatch:

jobs:
  dependency-audit:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: pip install -r requirements.txt
      - name: Dependency review
        uses: actions/dependency-review-action@v3

  secret-scan:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - name: GitHub Advanced Security secret scan
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: results.sarif
      - name: CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "security"
```

## Contributor Guidelines

### Proposing Changes
- Open an issue describing the problem, proposed solution, and impact.
- Link relevant metrics, logs, or incident reports.
- Provide risk assessment for production-facing changes.

### Review Criteria
- Code must follow style guides, include tests, and pass all CI checks.
- Documentation updates accompany behavioral changes when necessary.
- Reviewers confirm adherence to security, performance, and observability standards.

### Validation Process
- Merge only after successful CI, manual QA (if required), and stakeholder sign-off.
- Tag releases with semantic versions (e.g., `v1.4.0`).
- Update release notes summarizing changes, migrations, and rollback procedures.

## Troubleshooting and Optimization Tips
- **Copilot latency**: Disable unused plugins or reduce IDE load; verify network stability.
- **False-positive lint errors**: Update tooling, adjust configuration files, or add targeted ignores with justification.
- **Flaky tests**: Isolate external dependencies with mocks; ensure deterministic seeds and cleanup routines.
- **Security scan noise**: Triaging findings with severity labels; suppress only with documented acceptance.
- **Semantic release failures**: Confirm Conventional Commit compliance and inspect release logs for plugin errors.

## Maintenance Schedule
- Review this guide quarterly or after major architecture updates.
- Sync with evolving security policies, coding standards, and infrastructure changes.
- Archive historical versions and track revisions in the documentation repo.

---

**Standardizing excellence strengthens the reliability, performance, and safety of the Trading Bot Swarm ecosystem.**
