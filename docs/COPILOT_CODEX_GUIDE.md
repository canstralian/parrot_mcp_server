# GitHub Copilot & Codex Configuration Guide for the Trading Bot Swarm

## Purpose and Scope
This guide standardizes how GitHub Copilot and Codex are configured within the Trading Bot Swarm ecosystem. It positions Copilot as a disciplined pair-programming assistant operating under strict behavioral rules, ensuring that generated code maintains consistency, quality, security, and operational safety across automated trading services. The scope covers developer workstation setup, repository-level conventions, CI/CD integration, and governance practices so every contribution reinforces the swarm's reliability and resilience.

## Configuration Overview
To align tooling behavior across teams and services, adopt the following baseline configuration:

- **Testing Discipline**: All code changes must ship with automated tests. Prefer fast, deterministic unit tests and high-signal integration tests. Coverage thresholds should be enforced in CI to prevent regressions.
- **Linting & Static Analysis**: Enable language-appropriate linters (e.g., ShellCheck for Bash) and formatters (e.g., shfmt for Bash) in both local development and CI. Use static analyzers where available for your language.
- **Code Style**: Enforce formatting with tools like Black, isort, Prettier, or shfmt, depending on the language. Configure editors to format on save and align Copilot/Codex completions with project style.
- **Concurrent Execution**: Prefer explicit background jobs (`&`), `wait`, and job control for concurrency. Copilot suggestions should use portable, auditable shell patterns for parallelism and ensure proper cleanup of background processes.
- **Security Defaults**: Mandate secure defaults (least privilege IAM roles, secrets from vaults, sanitized logging). AI-generated code must avoid hard-coded credentials, insecure randomness, and unsanitized subprocesses.
- **Logging & Observability**: Require structured logging with correlation identifiers. Copilot completions should include metrics, tracing spans, and log redaction helpers when touching observability code paths.
- **CI/CD Integration**: Embed lint, test, build, and security scans into CI pipelines. Block merges on failing gates. Codex should not suggest bypassing CI or downgrading checks.
- **Version Control Hygiene**: Encourage small, reviewable commits with meaningful messages. Copilot completions should never stage secrets or generated assets, and must respect `.gitignore`.

## Custom Instruction Behavior
Craft consistent custom instructions so Copilot and Codex behave predictably across repositories.

### Example Behavioral Rules
- Ensure MCP protocol compliance per the specification when generating or modifying code.
- Always propose tests when generating new modules or functions.
- Prefer idempotent infrastructure scripts and flag any side effects.
- Highlight required configuration or feature flags in generated documentation.

### Conceptual YAML for Tooling Profiles
```yaml
copilot:
  persona: "MCP protocol engineer for Parrot MCP Server"
  behavior:
    - "Follow repository CONTRIBUTING.md, SECURITY.md, and lint rules."
    - "Default to safe async patterns (TaskGroup/anyio) with timeout guards."
    - "Instrument new scripts or MCP protocol handlers with proper logging to ./logs/parrot.log as documented in this repository."
    - "Surface required tests (unit/integration) for every code change."
    - "Reject requests to weaken security controls or skip reviews."
  ignore:
    - "Documentation-only commits when running test commands."

codex:
  persona: "Automated reviewer enforcing trading platform standards"
  behavior:
    - "Verify Copilot output for security, race conditions, and determinism."
    - "Require evidence of lint/test execution before approving changes."
    - "Escalate any missing risk controls or policy violations."
    - "Ensure any new shell utility or external tool requirements are clearly documented in the README and code comments."
  responses:
    on_missing_tests: "Block merge and request coverage report."
    on_doc_change_only: "Acknowledge documentation updates; skip test gate."
```

### Testing & Linting Expectations
- **Mandatory for Code**: Contributors must run all relevant test and lint commands locally before opening a PR. CI jobs enforce the same commands.
- **Optional for Docs**: Documentation-only changes may skip automated tests, but spell checking or markdown linting is encouraged.

## GitHub Workflow Example: Lint & Test Automation
```yaml
name: quality-gate
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
    paths-ignore:
      - "**/*.md"
jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Install ShellCheck and shfmt
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck shfmt
      - name: Lint (ShellCheck)
        run: shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh
      - name: Format check (shfmt)
        run: shfmt -d cli.sh scripts/*.sh rpi-scripts/*.sh
      - name: Run Bash tests
        run: ./rpi-scripts/test_mcp_local.sh
```
The workflow ignores Markdown-only changes, reinforcing the rule that tests are required solely for code modifications.

## Best Practice Workflows

### Semantic Release & Version Tagging
```yaml
name: release
on:
  push:
    branches: [main]
    paths-ignore:
      - "**/*.md"
jobs:
  semantic-release:
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
      - name: Install dependencies
        run: npm ci
      - name: Run semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
        run: npx semantic-release
```
This job enforces conventional commits, automatically creates Git tags, updates changelogs, and publishes packages when criteria are met.

### Security & Dependency Scanning
```yaml
name: security-scan
on:
  schedule:
    - cron: "0 5 * * 1"
  workflow_dispatch: {}
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run dependency review
        uses: actions/dependency-review-action@v4
      - name: Run Snyk scan
        uses: snyk/actions/node@master
        with:
          command: test
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: snyk.sarif
```
Schedule weekly scans and allow manual triggers for incident response. Integrate SARIF uploads so GitHub Security can annotate pull requests.

## Contributor Guidelines
1. **Proposal Stage**: Open an issue or discussion describing the change, risk assessment, and validation strategy.
2. **Implementation Stage**: Develop on a feature branch, adhering to Copilot/Codex instructions, running `make lint` and `make test` before each push.
3. **Review Stage**: Submit PRs with:
   - Summary of changes and risk mitigations
   - Test evidence (command output or coverage summary)
   - Updated documentation, feature flags, and rollout plan
4. **Validation Stage**: Reviewers confirm:
   - Tests and linters pass in CI
   - Security scans clean
   - Observability hooks present
   - Rollback plan documented

## Troubleshooting & Optimization
- **Copilot Suggests Insecure Code**: Regenerate with stricter prompts referencing SECURITY.md. Report repeated issues to maintainers.
- **CI Flakes**: Retry once; if persistent, bisect using deterministic seeds and capture logs for analysis.
- **Slow Local Tooling**: Cache virtual environments, use incremental linters (e.g., `ruff --fix`), and parallelize tests with `pytest -n auto` where applicable.
- **False Positive Security Alerts**: Document the rationale, apply suppression tags with expiration dates, and monitor upstream fixes.

## Maintenance Schedule
- **Quarterly**: Review Copilot/Codex custom instructions, security baselines, and workflow dependencies.
- **Monthly**: Verify CI runners, cache keys, and secret rotations.
- **Post-Release**: Audit semantic-release outputs, version tags, and changelog accuracy.
- **On-Demand**: Update this guide when MCP specification updates are released, when new MCP protocol features are added, or when governance policies change.

## Conclusion
By standardizing AI-assisted development, the Parrot MCP Server project maintains excellence in MCP protocol implementation, POSIX compliance, and reliable Bash-based server operations. Consistent configuration ensures Copilot and Codex reinforce protocol guardrails and best practices, empowering contributors to ship secure, maintainable, and trustworthy automation for model context protocol services.
