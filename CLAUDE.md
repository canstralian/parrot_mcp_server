# Parrot MCP Server — Claude Code Instructions

## Project Overview

Lightweight Model Context Protocol (MCP) server with a **dual Bash + Python architecture**:

- **Bash layer** (`rpi-scripts/`) — MCP server lifecycle, system automation, Raspberry Pi operations
- **Python layer** (`src/parrot_mcp_server/`) — Red/purple team orchestration tools
- **Standalone client** (`anthropic-nebius.py`) — DeepSeek-V3 REPL via Nebius AI (OpenAI-compatible)

Entry point: `pyproject.toml` → `parrot_mcp_server.server:main` (command: `parrot-mcp`)

---

## Critical Commands

```bash
# Always use cli.sh wrapper — never run scripts directly
./cli.sh <script_name>          # no .sh extension needed

# Server lifecycle
./rpi-scripts/start_mcp_server.sh
./rpi-scripts/stop_mcp_server.sh
tail -f ./logs/parrot.log       # follow runtime output

# Testing
bats rpi-scripts/tests/*.bats           # Bash unit tests (BATS framework)
./rpi-scripts/test_mcp_local.sh         # MCP protocol compliance harness

# Linting (mandatory before commits)
shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh
shfmt -w cli.sh scripts/*.sh rpi-scripts/*.sh

# Cron setup
./cli.sh setup_cron
```

---

## Key Files

| Path | Purpose |
|------|---------|
| `rpi-scripts/cli.sh` | Canonical script runner |
| `rpi-scripts/common_config.sh` | Centralized config + logging (all scripts must source this) |
| `rpi-scripts/scripts/` | Auto-discovered scripts exposed via `cli.sh` |
| `src/parrot_mcp_server/auth.py:38` | Engagement authorization gate |
| `anthropic-nebius.py` | Nebius AI REPL (DeepSeek-V3) |
| `pyproject.toml` | Python package config (Python ≥3.11, hatchling backend) |
| `docs/CONFIGURATION.md` | Config reference |
| `SECURITY.md` | IPC security details |

---

## Security-Critical Patterns

- **IPC is insecure by design**: uses `/tmp/mcp_in.json` and `/tmp/mcp_bad.json`
  - Production: set `PARROT_IPC_DIR=/run/parrot/` with `700` permissions
- **Engagement auth gate**: all tool calls in `src/parrot_mcp_server/auth.py` require active engagement with scope + time validation
- Never log raw API keys — `anthropic-nebius.py` uses PBKDF2 fingerprinting with per-process salt

---

## Coding Conventions

### Bash
- All scripts **must** source `rpi-scripts/common_config.sh` for config/logging
- Keep changes POSIX-friendly; preserve `#!/usr/bin/env bash` shebangs
- New scripts go in `scripts/`, must be `chmod +x`, named `scripts/<name>.sh`
- Explicit over clever — favor auditable logic, document edge cases in comments
- Rate limiter: custom AWK-based implementation in `common_config.sh:parrot_check_rate_limit()` — uses atomic file ops + sliding window

### Logging
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:$(date +%s%N)] message`
- Nanosecond-precision message IDs on every log entry
- Log levels filtered at write-time (see `common_config.sh:110-151`)

### MCP Protocol
- **Spec compliance is non-negotiable** — consult the MCP spec before protocol-affecting changes
- Semantic compliance > literal compliance (preserve intent, not just syntax)
- Protocol changes must update `rpi-scripts/test_mcp_local.sh`

---

## Python Specifics

- Python ≥ 3.11 required
- Build backend: `hatchling` (not setuptools)
- Key deps: `mcp>=1.0.0`, `openai` (for Nebius AI)
- `anthropic-nebius.py` env vars: `NEBIUS_API_KEY` (required), `DEEPSEEK_MODEL`, `DEEPSEEK_STREAM`, `DEEPSEEK_MAX_HISTORY`
- History trimming drops **message pairs** to avoid mid-exchange corruption

---

## Testing Notes

- Tests use **BATS** (Bash Automated Testing System), not pytest
- Test files: `rpi-scripts/tests/*.bats`
- Tests load config via `load ../common_config.sh`
- Rate limiter tests: `rpi-scripts/tests/rate_limiter.bats`

---

## References

- [AGENTS.md](AGENTS.md) — non-obvious patterns reference
- [.github/copilot-instructions.md](.github/copilot-instructions.md) — coding conventions
- [GEMINI.md](GEMINI.md) — MCP message format examples
- [SECURITY.md](SECURITY.md) — IPC security model
- [docs/CONFIGURATION.md](docs/CONFIGURATION.md) — full config reference
