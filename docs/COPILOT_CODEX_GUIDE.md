# GitHub Copilot & Codex Configuration Guide for the Trading Bot Swarm

## Purpose and Scope
This guide defines how GitHub Copilot and Codex should be configured and operated across the Trading Bot Swarm ecosystem to keep automation behavior consistent, secure, and production-grade.

- **Primary goal**: standardize code generation and review automation so every change meets the same quality, security, and delivery bar.
- **Audience**: contributors, maintainers, platform engineers, and CI/CD operators.
- **Operating model**: Copilot acts as a **pair programmer** with strict behavioral rules; Codex acts as an **automation gatekeeper** that enforces policy and quality controls.
- **Scope boundary**: this document covers behavior, quality gates, and workflow automation. It does not replace infrastructure-level hardening documentation.

## Two-Orchestration-Plane Model
Start by separating the system into two orchestration planes:

- **Base Package Plane (Control Plane)**: always-on operating substrate that governs inputs, scope control, command execution, artifacts, timeline, and report assembly.
- **Engagement Plane (Mission Workflow)**: engagement-specific orchestration layered on top of the base plane (for example, pentest workflows with recon, validation gates, exploitation controls, and client deliverables).

Mental model:

- **Base Package = control plane**
- **Pentest Package = mission workflow on top of the control plane**

### Base Package Orchestration (Always Present)
1. **Intake and scope validation**
2. **Run creation and directory initialization**
3. **Controlled execution wrapper**
4. **Artifact classification and storage**
5. **Timeline logging**
6. **Finding normalization**
7. **Draft report assembly**
8. **Run closure and archival**

#### 1) Target Intake and Validation
No workflow should execute before this control loop resolves authorized scope and binds it to a run.

```text
User input
   ↓
Target normalizer
   ↓
Scope validator
   ↓
Engagement record
   ↓
Run directory creation
```

Minimum outcomes:
- Normalize domains/IPs/apps into a standard schema.
- Reject malformed or unauthorized targets.
- Attach scope metadata and engagement context.
- Assign a unique run ID.
- Create the initial artifact tree.

#### 2) Execution Control Wrapper (Command Bus)
All tool calls should route through one wrapper rather than direct execution.

```text
Agent / workflow step
   ↓
Execution wrapper
   ├── policy check
   ├── parameter sanitization
   ├── command logging
   ├── timeout / retry control
   └── output capture
```

This wrapper is the base package spine: attributable, bounded, and reproducible execution.

#### 3) Artifact Routing
Raw output should be routed into durable, queryable storage.

```text
Command output
   ↓
Artifact classifier
   ├── raw logs
   ├── structured results
   ├── screenshots
   ├── HTTP evidence
   └── derived findings
```

#### 4) Timeline Logging and Evidence Chaining
Every major event belongs in a chronological ledger:

- `run_start`
- `tool_executed`
- `finding_candidate_detected`
- `validation_complete`
- `evidence_attached`
- `report_draft_updated`
- `run_closed`

#### 5) Finding Normalization
All tools should map to one internal finding schema.

```yaml
finding:
  finding_id: string
  title: string
  target: string
  asset_type: string
  source_tool: string
  severity_candidate: string
  confidence: string
  evidence_refs: [string]
  reproduction_refs: [string]
  status: string
```

#### 6) Report Assembly
Reporting is a core output, not a final garnish.

```text
Artifacts + timeline + normalized findings
   ↓
Report composer
   ↓
Draft report sections
   ↓
Exportable engagement summary
```

### Pentest Package Orchestration (Engagement Layer)
The pentest layer inherits the base control plane and adds bounded, client-oriented workflow control.

1. Scope intake
2. Engagement plan generation
3. Passive recon
4. Active enumeration
5. Attack surface map
6. Controlled scanning
7. Candidate issue extraction
8. Verification and false-positive reduction
9. Limited exploitation / proof of concept
10. Attack path correlation
11. Severity and business impact assignment
12. Technical report generation
13. Executive summary generation
14. Engagement closure

#### Pentest-Specific Controls
- **Planning orchestration**: scope → asset categories → test plan → task queue.
- **Phased recon**: passive recon → service discovery → endpoint enumeration → attack surface map.
- **Validation-gated scanning**: insert decision points before heavy scanners and before finding promotion.
- **Exploitation guardrails**: policy-driven choice of non-invasive validation vs limited PoC vs stop/escalate.
- **Path analysis**: chain findings into attack narratives mapped to business impact.
- **Human review gates**: after scope mapping, after initial scanning, before exploitation, before final severity, before report finalization.

### State-Driven Workflow Model
Use explicit run states with strict transition rules:

```text
NEW → SCOPED → MAPPED → ENUMERATED → SCANNED → VALIDATED → EXPLOITED_OPTIONALLY → REPORTED → CLOSED
```

Each state should define:
- allowed inputs,
- allowed tools,
- required artifacts,
- transition conditions.

Recommended build order:
1. Build base package control loop first.
2. Layer pentest engagement orchestrations second.

## Configuration Overview for Copilot and Codex
### Testing
- Run unit, integration, and simulation tests relevant to touched modules before merge.
- Require deterministic fixtures for protocol or trading-path behavior.
- Reject flaky-test bypasses; deflake or quarantine with owner approval and tracking issue.
- Documentation-only changes may skip runtime test suites.

### Linting and Static Analysis
- Enforce repository linters and formatters (for example: `shellcheck`, `shfmt`, `ruff`, `mypy`, `eslint`).
- Do not suppress warnings without explicit reviewer-visible justification.
- Keep tool versions pinned in CI for reproducibility.

### Code Style and Async Patterns
- Prefer pure core logic and side-effect boundaries in adapters.
- Require explicit type boundaries on public interfaces.
- In async flows: await tasks, propagate cancellation, set timeouts, and bound concurrency.
- Avoid broad exception swallowing; preserve context IDs in errors.

### Security Defaults
- Never generate, store, or log secrets in plaintext.
- Use least-privilege tokens and scoped automation identities.
- Verify TLS by default; sanitize untrusted input.
- Redact sensitive payload fields in logs and traces.

### Logging and Observability
- Emit structured logs with run IDs and correlation IDs.
- Capture metrics by component, workflow state, and latency class.
- Trace critical external calls and long-running orchestration stages.

### CI/CD Integration
- Apply the same quality gates to AI-generated and human-generated code.
- Block merges on failing lint, tests, or security checks.
- Make report artifacts and test outputs available in workflow artifacts.

### Version Control Discipline
- Use conventional commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`).
- Keep commits atomic and scoped to a single intent.
- Prefer protected-branch PR merges over direct pushes.

## Custom Instruction Behavior for Codex and Copilot
### Example Behavioral Rules
- Generate complete, runnable changes with relevant tests.
- Refuse insecure patterns (hardcoded secrets, disabled verification, unsafe eval paths).
- Propose observability updates when new workflows or critical paths are introduced.
- Flag ambiguous requirements instead of inventing risky assumptions.

### Conceptual YAML: Full Custom Instructions
```yaml
assistant_policy:
  repository: trading-bot-swarm
  default_mode: strict_pair_programming

copilot:
  role: pair_programmer
  objectives:
    - "Produce complete, secure, testable code changes."
    - "Follow project style, linting, and async safety requirements."
  required_checks:
    - "Recommend or generate tests for every code change."
    - "Recommend linting/type-check commands for touched stacks."
  hard_rules:
    - "Do not create or expose credentials, tokens, or private keys."
    - "Do not bypass failing tests with silent skips."
    - "Do not suggest disabling TLS verification in production paths."
  doc_only_behavior:
    - "If only docs changed, skip runtime tests and run docs lint/link checks only."

codex:
  role: automation_gatekeeper
  objectives:
    - "Validate generated and human code against quality/security policy."
    - "Enforce deterministic workflow transitions and reportability."
  merge_policy:
    block_on:
      - lint_fail
      - test_fail
      - typecheck_fail
      - security_scan_fail
      - missing_required_review
  orchestration_policy:
    require_execution_wrapper: true
    require_artifact_routing: true
    require_timeline_events: true
    require_finding_normalization: true
  doc_only_behavior:
    code_change_detection:
      include: ["**/*.py", "**/*.ts", "**/*.js", "**/*.sh", "Dockerfile", "Makefile"]
      exclude: ["**/*.md", "docs/**"]
    when_no_code_files_changed:
      run:
        - markdownlint
        - link-check
      skip:
        - unit-tests
        - integration-tests
        - runtime-simulations
```

### Tests and Linters Rule (Critical)
- For **code changes**: run tests and linters before merge.
- For **documentation-only changes**: run docs quality checks; skip runtime suites.

## GitHub Workflow Example: Lint and Test Automation
Trigger the quality gate on pushes and PRs to protected branches, ignoring markdown-only changes.

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
  quality-gate:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Lint shell
        run: |
          shellcheck rpi-scripts/cli.sh rpi-scripts/scripts/*.sh
          shfmt -d rpi-scripts/cli.sh rpi-scripts/scripts/*.sh

      - name: Lint and type-check Python
        run: |
          ruff check .
          mypy .

      - name: Run tests
        run: |
          pytest -q --maxfail=1 --disable-warnings

      - name: Upload test artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: quality-gate-artifacts
          path: |
            .pytest_cache
            reports/
```

Quality gate job stages:
1. Checkout source.
2. Install runtime/toolchain dependencies.
3. Run lint checks.
4. Run type checks.
5. Run test suite.
6. Publish artifacts.

## Best-Practice Workflows
### Semantic Release and Version Tagging
```yaml
name: release
on:
  push:
    branches: [main]

jobs:
  semantic-release:
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
      - name: Install dependencies
        run: npm ci
      - name: Run semantic-release
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
    branches: [main]
  workflow_dispatch: {}

jobs:
  dependency-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Python dependency audit
        run: |
          python -m pip install --upgrade pip
          pip install pip-audit
          pip-audit --desc --strict
      - name: Node dependency audit
        run: npm audit --audit-level=high

  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: gitleaks/gitleaks-action@v2

  codeql:
    permissions:
      actions: read
      contents: read
      security-events: write
    uses: github/codeql-action/codeql@v3
    with:
      languages: python,javascript
      queries: security-extended
```

## Contributor Guidelines
### Proposing Changes
- Open a proposal issue with context, objective, and expected impact.
- Include risk assessment, rollback strategy, and observability updates.
- Identify whether the change touches base-plane controls, engagement workflows, or both.

### Review Criteria
- **Correctness**: implementation matches intended behavior and orchestration stage.
- **Quality**: lint, type-check, and tests pass.
- **Security**: secure defaults preserved; dependency and secret scans clean.
- **Operability**: logs, metrics, timeline events, and artifacts are sufficient for investigation.
- **Deliverability**: commit semantics and release notes are clear.

### Validation Process
- Run required local/CI quality gates.
- Attach evidence for tests and scans in PR checks.
- Complete domain-owner review where applicable.
- Confirm release impact classification (patch/minor/major) is accurate.

## Troubleshooting and Optimization
- **Copilot output drifts from standards**: tighten prompt context and reference custom instruction policy directly.
- **Codex blocks valid PRs**: inspect which gate failed (lint/test/type/security/review) and resolve root cause.
- **Flaky tests**: add deterministic fixtures, isolate network dependencies, and enforce explicit timeouts.
- **Noisy findings pipeline**: tighten finding normalization, add validation gates, and improve evidence thresholds.
- **Semantic-release failures**: verify commit message conventions, token scopes, and branch protection settings.
- **Slow CI**: cache dependencies, shard test jobs, and parallelize independent lint/type/test stages.

## Maintenance Schedule
- **Monthly lightweight review**: check command/tooling accuracy and dead links.
- **Quarterly policy review**: update coding, security, and release standards.
- **Post-incident review**: patch this guide after major failures or process gaps.
- **Versioning**: track revisions with dated changelog entries in docs updates.

## Closing Note
The goal is to standardize excellence: aligning Copilot, Codex, and contributors around one disciplined operating model that continuously improves reliability, performance, and safety across the trading ecosystem.
