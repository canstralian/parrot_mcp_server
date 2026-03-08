# Debug Mode — Parrot MCP Server

## Debugging Non-Obvious Patterns

### Log Message Tracing
- All logs include nanosecond-precision message IDs: `[msgid:$(date +%s%N)]`
- Grep logs by msgid: `grep "msgid:1234567890123456789" logs/parrot.log`
- Log files: [`common_config.sh:31-34`](../../rpi-scripts/common_config.sh:31-34)

### Debug Mode Activation
- Set `PARROT_DEBUG=true` in [`config.env`](../../rpi-scripts/config.env)
- Enables stdout output for all log levels
- Trace mode: `PARROT_TRACE=true` enables `set -x` (see [`common_config.sh:461-464`](../../rpi-scripts/common_config.sh:461-464))

### IPC Debugging
- Watch IPC files: `watch -n 1 'ls -la /tmp/mcp_*.json'`
- IPC files are in `/tmp` by default (insecure) — see [`SECURITY.md:22-36`](../../SECURITY.md:22-36)
- Override with `PARROT_IPC_DIR=/run/parrot/` for production

### Rate Limiter Debugging
- Rate limit log: [`PARROT_RATE_LIMIT_FILE`](../../rpi-scripts/common_config.sh:83)
- Format: `user:operation:timestamp` (one per line)
- Manual cleanup: `rm -f $PARROT_RATE_LIMIT_FILE`
- Test: `bats rpi-scripts/tests/rate_limiter.bats`

### Script Execution Debugging
- CLI logs errors to: [`rpi-scripts/cli_error.log`](../../rpi-scripts/cli.sh:56)
- Message IDs in CLI: [`cli.sh:62-64`](../../rpi-scripts/cli.sh:62-64)
- Trap handler logs unexpected exits: [`cli.sh:198-202`](../../rpi-scripts/cli.sh:198-202)

### Test Debugging
- BATS verbose mode: `bats -t rpi-scripts/tests/*.bats`
- Test setup/teardown in each `.bats` file creates temp dirs
- Tests source config: `load ../common_config.sh` pattern

### MCP Protocol Debugging
- Test harness: [`rpi-scripts/test_mcp_local.sh`](../../rpi-scripts/test_mcp_local.sh)
- Server logs: [`PARROT_SERVER_LOG`](../../rpi-scripts/common_config.sh:31)
- Protocol compliance: consult [MCP spec](https://modelcontextprotocol.io/specification)

### Engagement Authorization Debugging
- Check active engagements: inspect `_ACTIVE_ENGAGEMENTS` dict in [`auth.py:29`](../../src/parrot_mcp_server/auth.py:29)
- Authorization failures raise `PermissionError` with detailed messages
- Engagement fingerprints in audit logs: [`auth.py:68-71`](../../src/parrot_mcp_server/auth.py:68-71)

### anthropic-nebius.py Debugging
- Set `DEEPSEEK_LOG_LEVEL=DEBUG` for verbose output
- API key fingerprint logged (never raw key): [`anthropic-nebius.py:100-112`](../../anthropic-nebius.py:100-112)
- Retry logic with full jitter: [`anthropic-nebius.py:192-200`](../../anthropic-nebius.py:192-200)
- Stream interruption handling: [`anthropic-nebius.py:283-287`](../../anthropic-nebius.py:283-287)
