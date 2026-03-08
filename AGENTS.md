# Parrot MCP Server — AI Assistant Guide

## Critical Non-Obvious Patterns

### Dual Architecture: Bash + Python Hybrid
- **Bash scripts** in [`rpi-scripts/`](rpi-scripts/) handle MCP server lifecycle, system automation, and Raspberry Pi operations
- **Python code** in [`src/parrot_mcp_server/`](src/parrot_mcp_server/) provides red/purple team orchestration tools
- Entry point: [`pyproject.toml`](pyproject.toml:20) defines `parrot-mcp` command → `parrot_mcp_server.server:main`
- Standalone client: [`anthropic-nebius.py`](anthropic-nebius.py) is a DeepSeek-V3 REPL via Nebius AI (OpenAI-compatible)

### Bash Script Execution Model
- **Never run scripts directly** — use [`rpi-scripts/cli.sh`](rpi-scripts/cli.sh) wrapper: `./cli.sh <script_name>`
- Scripts in [`rpi-scripts/scripts/`](rpi-scripts/scripts/) are auto-discovered by CLI (no `.sh` extension in command)
- All scripts **must** source [`rpi-scripts/common_config.sh`](rpi-scripts/common_config.sh) for centralized config/logging

### Security-Critical IPC Pattern
- **INSECURE by design**: Uses `/tmp/mcp_in.json` and `/tmp/mcp_bad.json` for IPC (see [`SECURITY.md`](SECURITY.md:22-36))
- Production deployments **must** override `PARROT_IPC_DIR` to `/run/parrot/` with 700 permissions
- Engagement authorization gate: [`src/parrot_mcp_server/auth.py`](src/parrot_mcp_server/auth.py:38) — all tool calls require active engagement with scope/time validation

### Rate Limiting Implementation
- Custom AWK-based rate limiter in [`common_config.sh:parrot_check_rate_limit()`](rpi-scripts/common_config.sh:377-455)
- Uses atomic file operations with temp files for concurrent safety
- Cleans expired entries on every check (sliding window, not fixed buckets)
- Test coverage: [`rpi-scripts/tests/rate_limiter.bats`](rpi-scripts/tests/rate_limiter.bats)

### Testing Framework: BATS
- Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System), not pytest/unittest
- Run: `bats rpi-scripts/tests/*.bats` (requires `bats` installed)
- Tests load config via `load ../common_config.sh` pattern

### Logging with Message IDs
- All logs include nanosecond-precision message IDs: `[msgid:$(date +%s%N)]`
- Structured format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:...] message`
- Log levels filtered at write-time, not collection-time (see [`common_config.sh:110-151`](rpi-scripts/common_config.sh:110-151))

### Spec-Driven Development
- **MCP protocol compliance is non-negotiable** — consult [MCP spec](https://modelcontextprotocol.io/specification) before changes
- Changes affecting protocol must update [`rpi-scripts/test_mcp_local.sh`](rpi-scripts/test_mcp_local.sh) test harness
- Semantic compliance > literal compliance (preserve intent, not just syntax)

### Linting/Formatting
- **ShellCheck** and **shfmt** are mandatory: `shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh`
- Format: `shfmt -w cli.sh scripts/*.sh rpi-scripts/*.sh`
- CI enforces both on every push (see [`.cursorrules`](.cursorrules:39-42))

### Cron Automation
- Setup: `./cli.sh setup_cron` installs all maintenance jobs
- Schedules defined in [`common_config.sh`](rpi-scripts/common_config.sh:86-88): `PARROT_CRON_DAILY`, `PARROT_CRON_BACKUP`, `PARROT_CRON_HEALTH`
- Changes to scheduling **must** update [`rpi-scripts/scripts/setup_cron.sh`](rpi-scripts/scripts/setup_cron.sh)

### Python Dependencies
- Requires Python ≥3.11 (see [`pyproject.toml`](pyproject.toml:10))
- Uses `hatchling` build backend (not setuptools)
- MCP SDK: `mcp>=1.0.0` (Model Context Protocol library)
- OpenAI client for Nebius AI integration

### anthropic-nebius.py Quirks
- **Full jitter exponential backoff** for retries (see [`anthropic-nebius.py:192-200`](anthropic-nebius.py:192-200))
- API key fingerprinting uses PBKDF2 with per-process salt (never logs raw key)
- History trimming drops **pairs** of messages to avoid mid-exchange corruption
- Env vars: `NEBIUS_API_KEY` (required), `DEEPSEEK_MODEL`, `DEEPSEEK_STREAM`, `DEEPSEEK_MAX_HISTORY`
