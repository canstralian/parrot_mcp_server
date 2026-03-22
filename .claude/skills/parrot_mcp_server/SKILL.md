# Parrot MCP Server — Skill Profile

## Project Summary

Lightweight Model Context Protocol (MCP) server with a dual Bash + Python architecture:

- **Bash layer** (`rpi-scripts/`) — MCP server lifecycle, system automation, Raspberry Pi operations
- **Python layer** (`src/parrot_mcp_server/`) — Red/purple team orchestration tools
- **Standalone client** (`anthropic-nebius.py`) — DeepSeek-V3 REPL via Nebius AI

## Detected Workflows

| Workflow | Description |
|---|---|
| `feature-development` | Standard feature implementation: branch → implement → shellcheck/shfmt → bats test → commit → PR |
| `github-workflow-permissions-fix` | Add `permissions: contents: read` to GitHub Actions workflows to resolve security scanning alerts |
| `documentation-update` | Update project documentation files (CLAUDE.md, AGENTS.md, docs/) with new content or corrections |
| `log-file-management` | Handle log files in git tracking — add to `.gitignore` or remove from tracking |
| `copilot-guide-iteration` | Iteratively update `.github/copilot-instructions.md` through multiple small, focused commits |
| `security-hardening` | Apply security fixes: input validation, quoting, permissions, shellcheck warnings |
| `bats-test-expansion` | Add BATS test cases for new functions or edge cases in `rpi-scripts/tests/*.bats` |

## Critical Patterns

### Script Runner
Always use `./cli.sh <name>` (no `.sh` extension) — never invoke scripts directly.

### Required Preamble (all Bash scripts)
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../rpi-scripts/common_config.sh"
```

### Naming Conventions
- Env vars: `PARROT_*` (uppercase)
- Functions: `parrot_*()` (lowercase)
- New scripts: `rpi-scripts/scripts/<name>.sh`, must be `chmod +x`

### Logging Format
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:$(date +%s%N)] message
```
Use `parrot_info`, `parrot_warn`, `parrot_error`, `parrot_debug` helpers.

### MCP Protocol
Spec compliance is non-negotiable. Protocol changes must update `rpi-scripts/test_mcp_local.sh`.

### Pre-commit Checklist
```bash
shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh
shfmt -w cli.sh scripts/*.sh rpi-scripts/*.sh
bats rpi-scripts/tests/*.bats
```

## Key Entry Points

| File | Purpose |
|---|---|
| `rpi-scripts/common_config.sh` | Centralized config + logging (must be sourced) |
| `rpi-scripts/cli.sh` | Canonical script runner |
| `src/parrot_mcp_server/auth.py:38` | Engagement authorization gate |
| `anthropic-nebius.py` | Nebius AI REPL (DeepSeek-V3) |
| `pyproject.toml` | Python package config (Python ≥3.11, hatchling) |
