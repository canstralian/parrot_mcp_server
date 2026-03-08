# Ask Mode — Parrot MCP Server

## Project-Specific Knowledge

### Architecture Overview
- **Dual architecture**: Bash scripts (Raspberry Pi automation) + Python (red/purple team tools)
- Bash handles MCP server lifecycle, Python provides security orchestration
- Entry point: `parrot-mcp` command → [`src/parrot_mcp_server/server:main`](../../src/parrot_mcp_server/server.py)

### Key Documentation
- Configuration guide: [`docs/CONFIGURATION.md`](../../docs/CONFIGURATION.md)
- Security policy: [`SECURITY.md`](../../SECURITY.md) — **critical**: IPC is insecure by design
- IPC security details: [`docs/IPC_SECURITY.md`](../../docs/IPC_SECURITY.md)
- Rate limiter design: [`docs/RATE_LIMITER.md`](../../docs/RATE_LIMITER.md)
- Troubleshooting: [`docs/TROUBLESHOOTING.md`](../../docs/TROUBLESHOOTING.md)

### Non-Standard Patterns
- **Script execution**: Always use `./cli.sh <script_name>`, never run scripts directly
- **Config loading**: All scripts source [`common_config.sh`](../../rpi-scripts/common_config.sh) for centralized config
- **Testing**: Uses BATS (Bash Automated Testing System), not pytest
- **Build system**: Uses `hatchling`, not setuptools

### Security Model
- Engagement-based authorization: [`auth.py`](../../src/parrot_mcp_server/auth.py)
- All tool calls require active engagement with scope/time validation
- IPC files in `/tmp` are **intentionally insecure** for development
- Production requires `PARROT_IPC_DIR=/run/parrot/` with 700 permissions

### Rate Limiting
- Custom AWK-based implementation (not Redis/database)
- Sliding window with atomic file operations
- Configured via `PARROT_RATE_LIMIT` and `PARROT_RATE_LIMIT_WINDOW`
- See [`common_config.sh:377-455`](../../rpi-scripts/common_config.sh:377-455)

### Logging System
- Structured logs with nanosecond-precision message IDs
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:...] message`
- Log level filtering at write-time, not collection-time
- Functions: `parrot_log()`, `parrot_info()`, `parrot_warn()`, `parrot_error()`

### MCP Protocol Compliance
- Spec-driven development: consult [MCP spec](https://modelcontextprotocol.io/specification) before changes
- Test harness: [`rpi-scripts/test_mcp_local.sh`](../../rpi-scripts/test_mcp_local.sh)
- Semantic compliance > literal compliance

### anthropic-nebius.py
- Standalone DeepSeek-V3 REPL via Nebius AI (OpenAI-compatible)
- Full jitter exponential backoff for retries
- API key fingerprinting (never logs raw key)
- History trimming drops message pairs to avoid corruption
- Env vars: `NEBIUS_API_KEY`, `DEEPSEEK_MODEL`, `DEEPSEEK_STREAM`, `DEEPSEEK_MAX_HISTORY`

### Cron Automation
- Setup: `./cli.sh setup_cron`
- Schedules: `PARROT_CRON_DAILY`, `PARROT_CRON_BACKUP`, `PARROT_CRON_HEALTH`
- Defined in [`common_config.sh:86-88`](../../rpi-scripts/common_config.sh:86-88)
