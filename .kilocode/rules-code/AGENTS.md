# Code Mode — Parrot MCP Server

## Non-Obvious Code Patterns

### Script Wrapper Pattern
- **Never edit scripts in [`rpi-scripts/scripts/`](../../rpi-scripts/scripts/) directly** — always test via `./cli.sh <script_name>`
- Scripts auto-discovered by CLI without `.sh` extension
- All scripts must source [`common_config.sh`](../../rpi-scripts/common_config.sh) first

### Python Entry Points
- Main command: `parrot-mcp` → [`src/parrot_mcp_server/server:main`](../../src/parrot_mcp_server/server.py)
- Standalone REPL: [`anthropic-nebius.py`](../../anthropic-nebius.py) (DeepSeek-V3 via Nebius AI)
- Build backend: `hatchling` (not setuptools) — see [`pyproject.toml`](../../pyproject.toml:2)

### Security Gates
- All tool calls **must** pass through [`auth.py:require_authorization()`](../../src/parrot_mcp_server/auth.py:38)
- Engagement validation checks: scope, time window, authorized contact
- IPC files in `/tmp` are **insecure by design** — override `PARROT_IPC_DIR` for production

### Rate Limiter
- Custom AWK-based implementation in [`common_config.sh:377-455`](../../rpi-scripts/common_config.sh:377-455)
- Atomic file operations with temp files (not database)
- Sliding window cleanup on every check
- Test with: `bats rpi-scripts/tests/rate_limiter.bats`

### Logging
- Message IDs use nanosecond precision: `[msgid:$(date +%s%N)]`
- Log level filtering at write-time (see [`common_config.sh:110-151`](../../rpi-scripts/common_config.sh:110-151))
- Use `parrot_log()`, `parrot_info()`, `parrot_warn()`, `parrot_error()` functions

### Mandatory Linting
- **ShellCheck**: `shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh`
- **shfmt**: `shfmt -w cli.sh scripts/*.sh rpi-scripts/*.sh`
- CI enforces both — see [`.cursorrules:39-42`](../../.cursorrules:39-42)

### Testing Framework
- Bash tests use **BATS** (not pytest): `bats rpi-scripts/tests/*.bats`
- Tests load config: `load ../common_config.sh`
- Python tests: (not yet implemented)

### Cron Jobs
- Install: `./cli.sh setup_cron`
- Schedules in [`common_config.sh:86-88`](../../rpi-scripts/common_config.sh:86-88)
- Changes require updating [`scripts/setup_cron.sh`](../../rpi-scripts/scripts/setup_cron.sh)

### anthropic-nebius.py Specifics
- Full jitter exponential backoff: [`anthropic-nebius.py:192-200`](../../anthropic-nebius.py:192-200)
- API key fingerprinting: PBKDF2 with per-process salt (never logs raw key)
- History trimming drops **pairs** to avoid mid-exchange corruption
- Required env: `NEBIUS_API_KEY`
