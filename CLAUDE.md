# CLAUDE.md — Parrot MCP Server Project

This file provides comprehensive guidance for Claude AI assistants working with the Parrot MCP Server codebase. It outlines the project structure, development workflows, coding conventions, and key considerations for effective collaboration.

---

## Project Overview

**Parrot MCP Server** is a lightweight, modular implementation of the Model Context Protocol (MCP) built entirely in POSIX-compliant Bash. It's designed for Raspberry Pi 5 and edge computing environments, emphasizing transparency, auditability, and portability.

### Key Characteristics

- **Language**: Pure POSIX Bash (no Node.js, Python, or other runtimes)
- **Purpose**: Structured message exchange between AI agents and local tools/services
- **Status**: Experimental/prototype (not production-ready)
- **Philosophy**: Spec-driven development, minimal dependencies, maximum transparency

### Core Architecture

The server operates as an adaptive system with five interconnected layers:

1. **Signal Reactor** — Non-blocking event handler for connections and I/O
2. **Configuration Bus** — Dynamic parameter tuning without restarts
3. **Security Core** — Adaptive authentication, sandboxing, and monitoring
4. **Plugin Modules** — Isolated, reversible capability extensions
5. **Observability Bus** — Structured logging, metrics, and forensic timelines

```
External Clients (HTTP, WebSocket, CLI)
                ↓
         Signal Reactor
                ↓
   ┌────────────┼────────────┐
   │            │            │
Security    Config Bus    Plugins
   │            │            │
   └────────────┼────────────┘
                ↓
       Observability Bus
```

---

## Repository Structure

```
parrot_mcp_server/
├── rpi-scripts/              # Primary codebase
│   ├── cli.sh                # Main CLI entry point
│   ├── common_config.sh      # Centralized configuration & utilities
│   ├── start_mcp_server.sh   # Start the MCP server
│   ├── stop_mcp_server.sh    # Stop the MCP server
│   ├── test_mcp_local.sh     # Local MCP protocol testing
│   ├── config.env.example    # Configuration template
│   └── scripts/              # Executable utility scripts
│       ├── health_check.sh
│       ├── daily_workflow.sh
│       ├── system_update.sh
│       ├── clean_cache.sh
│       └── ...
├── docs/                     # Documentation
│   ├── CONFIGURATION.md
│   ├── LOGGING.md
│   ├── RATE_LIMITER.md
│   ├── IPC_SECURITY.md
│   ├── TROUBLESHOOTING.md
│   └── COPILOT_CODEX_GUIDE.md
├── logs/                     # Runtime logs
│   └── parrot.log            # Main server log
├── .github/                  # GitHub configuration
│   ├── copilot-instructions.md
│   └── ...
├── README.md                 # Project overview
├── CONTRIBUTING.md           # Contribution guidelines
├── SECURITY.md               # Security policy & known issues
├── GEMINI.md                 # Gemini AI integration guide
├── .cursorrules              # Cursor AI coding standards
└── .env.example              # Root environment template
```

### Key Directories

- **`rpi-scripts/`**: Core implementation. All executable scripts live here or in `rpi-scripts/scripts/`
- **`docs/`**: Technical documentation for specific subsystems
- **`logs/`**: Runtime logs for debugging and auditing
- **`.github/`**: GitHub workflows, templates, and AI assistant instructions

---

## Development Workflows

### Quick Start

1. **Clone and Setup**
   ```bash
   git clone <repo-url>
   cd parrot_mcp_server
   cd rpi-scripts
   cp config.env.example config.env
   # Edit config.env with your settings
   ```

2. **Start the Server**
   ```bash
   ./rpi-scripts/start_mcp_server.sh
   tail -f ./logs/parrot.log  # Monitor runtime
   ```

3. **Test Locally**
   ```bash
   ./rpi-scripts/test_mcp_local.sh
   ```

4. **Run Utility Scripts**
   ```bash
   ./rpi-scripts/cli.sh <script_name> [args]
   # Example:
   ./rpi-scripts/cli.sh health_check
   ```

### Development Cycle

1. **Read Before Modifying**: Always read existing code before making changes
2. **Follow MCP Spec**: All protocol-related changes must comply with the official MCP specification
3. **Write Tests**: Add tests to `tests/` or extend `test_mcp_local.sh`
4. **Lint & Format**: Run ShellCheck and shfmt before committing
5. **Log Everything**: Use structured logging with message IDs
6. **Document Edge Cases**: Comment protocol boundaries and error handling

### Testing & Validation

```bash
# Static analysis
shellcheck rpi-scripts/cli.sh rpi-scripts/scripts/*.sh

# Format check
shfmt -w rpi-scripts/cli.sh rpi-scripts/scripts/*.sh

# Protocol compliance
./rpi-scripts/test_mcp_local.sh

# Manual testing
./rpi-scripts/start_mcp_server.sh
# Send test messages to /tmp/mcp_in.json
# Monitor logs/parrot.log
./rpi-scripts/stop_mcp_server.sh
```

---

## Coding Conventions

### Script Structure

All scripts must follow this template:

```bash
#!/usr/bin/env bash
# script_name.sh - Brief description
# Usage: ./script_name.sh [args]

set -euo pipefail

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"

# Initialize logging
parrot_init_log_dir
parrot_info "MSG_ID_001" "Script started"

# Main logic here
main() {
    # Use utility functions from common_config.sh
    parrot_validate_email "$email" || parrot_die "Invalid email"

    # Log with message IDs
    parrot_info "MSG_ID_002" "Processing data"

    # Handle errors explicitly
    if ! some_command; then
        parrot_error "MSG_ID_ERR_001" "Command failed"
        return 1
    fi
}

# Execute
main "$@"
```

### Mandatory Practices

1. **Shebang**: Always use `#!/usr/bin/env bash`
2. **Error Handling**: Always use `set -euo pipefail`
3. **POSIX Compliance**: Avoid bashisms when possible; keep scripts portable
4. **Naming**: Use `snake_case` for functions and variables, `kebab-case` for files
5. **Permissions**: Make scripts executable with `chmod +x`
6. **Configuration**: Source `common_config.sh` for centralized settings
7. **Logging**: Use `parrot_info`, `parrot_warn`, `parrot_error` functions with message IDs
8. **Input Validation**: Validate all user input and file paths
9. **Comments**: Document non-obvious logic, edge cases, and protocol decisions

### File Naming

- Scripts: `<action>_<noun>.sh` (e.g., `check_disk.sh`, `backup_home.sh`)
- Configuration: `config.env`, `common_config.sh`
- Documentation: `UPPERCASE.md` (e.g., `README.md`, `SECURITY.md`)

### Code Style

- **Indentation**: 2 spaces (no tabs)
- **Line Length**: Max 100 characters where practical
- **Functions**: Short, composable, single-purpose
- **Variables**: Quote all variable expansions: `"$var"`, `"${var}"`
- **Conditionals**: Use `[[ ]]` for bash conditionals, `[ ]` for POSIX
- **Loops**: Prefer `for` over `while read` for simple iterations

---

## Configuration System

### Overview

The project uses a centralized configuration system via `rpi-scripts/common_config.sh`:

- **Defaults**: All settings have sensible defaults
- **Overrides**: User settings in `rpi-scripts/config.env`
- **Validation**: Built-in functions for secure input handling
- **Utilities**: Common functions for logging, error handling, etc.

### Key Configuration Variables

```bash
# Paths
PARROT_BASE_DIR="/path/to/parrot_mcp_server"
PARROT_LOG_DIR="./logs"
PARROT_IPC_DIR="/tmp"  # INSECURE - see SECURITY.md

# Logging
PARROT_SERVER_LOG="./logs/parrot.log"
PARROT_LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
PARROT_LOG_MAX_SIZE="10M"

# MCP Server
PARROT_MCP_INPUT="/tmp/mcp_in.json"
PARROT_MCP_BAD="/tmp/mcp_bad.json"
PARROT_MCP_PORT="3000"

# Monitoring
PARROT_DISK_THRESHOLD="80"
PARROT_LOAD_THRESHOLD="2.0"
PARROT_MEM_THRESHOLD="90"

# Security
PARROT_VALIDATION_LEVEL="STRICT"
PARROT_MAX_INPUT_SIZE="1048576"  # 1MB

# Development
PARROT_DEBUG="false"
PARROT_DRY_RUN="false"
```

### Using Configuration in Scripts

```bash
source "${SCRIPT_DIR}/common_config.sh"

# Access variables
parrot_info "Logging to: $PARROT_SERVER_LOG"

# Use validation functions with explicit error handling
parrot_validate_email "$email" || { parrot_error "Invalid email"; exit 1; }
parrot_validate_path "$file_path" || { parrot_error "Invalid path"; exit 1; }
parrot_validate_json "$json_file" || { parrot_error "Invalid JSON"; exit 1; }
```

---

## Logging & Observability

### Structured Logging

All logs use structured format with auto-generated numeric message IDs (derived from timestamps) for traceability:

```bash
parrot_info "MCP Server starting on port $PARROT_MCP_PORT"
parrot_warn "Disk usage at ${usage}% exceeds threshold"
parrot_error "Failed to process message: $error_msg"
```

### Log Levels

- **DEBUG**: Detailed diagnostic information (set `PARROT_DEBUG=true`)
- **INFO**: General informational messages
- **WARN**: Warning messages (potential issues)
- **ERROR**: Error messages (operation failures)

### Log Files

- **`logs/parrot.log`**: Main server log (all operations)
- **`logs/cli_error.log`**: CLI error log
- **`logs/health_check.log`**: Health check results
- **`logs/daily_workflow.log`**: Scheduled workflow logs
- **`logs/rate_limit.log`**: Rate limiting events

### Monitoring Logs

```bash
# Follow main log
tail -f logs/parrot.log

# Search for errors
grep "ERROR" logs/parrot.log

# Filter by message ID
grep "MSG_STARTUP" logs/parrot.log

# View last 100 lines
tail -n 100 logs/parrot.log
```

---

## MCP Protocol Integration

### Message Format

The server expects JSON-RPC 2.0 formatted MCP messages:

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "run_script",
    "arguments": {
      "script": "check_disk",
      "args": ["--verbose"]
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Disk check completed. Usage: 45%"
      }
    ]
  }
}
```

**Error:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found",
    "data": {"script": "invalid_script"}
  }
}
```

### Testing MCP Locally

```bash
# Start server
./rpi-scripts/start_mcp_server.sh

# Send test message
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"health_check"}}' > /tmp/mcp_in.json

# Monitor logs
tail -f logs/parrot.log

# Stop server
./rpi-scripts/stop_mcp_server.sh
```

### Adding New MCP Tools

1. Create script in `rpi-scripts/scripts/`
2. Make executable: `chmod +x rpi-scripts/scripts/my_tool.sh`
3. Add to CLI routing in `cli.sh` if needed
4. Update tests in `test_mcp_local.sh`
5. Document in `docs/` if complex

---

## Security Considerations

### Known Vulnerabilities

The project has documented security issues (see `SECURITY.md`):

1. **Insecure IPC** (CRITICAL): Uses `/tmp/mcp_in.json` — vulnerable to race conditions and symlink attacks
2. **Missing Input Validation** (HIGH): Not all scripts validate user input
3. **No Authentication** (HIGH): No auth/authz mechanism implemented
4. **Insecure Cron Setup** (MEDIUM): Potential privilege escalation

### Security Best Practices

When contributing code:

- **Validate All Input**: Use `parrot_validate_*` functions from `common_config.sh`
- **Avoid Command Injection**: Quote variables, use arrays for commands
- **Check File Permissions**: Verify file ownership and permissions before operations
- **Sanitize Paths**: Prevent path traversal with `parrot_validate_path`
- **Limit Input Size**: Respect `PARROT_MAX_INPUT_SIZE`
- **Log Security Events**: Use message IDs for auditing
- **Never Log Secrets**: Avoid logging sensitive data

### Input Validation Example

```bash
# BAD - vulnerable to command injection
eval "ls $user_input"

# GOOD - validate and sanitize
if parrot_validate_path "$user_input"; then
    ls -la "$user_input"
else
    parrot_error "ERR_001" "Invalid path: $user_input"
    return 1
fi
```

---

## Common Tasks

### Adding a New Script

1. **Create Script**
   ```bash
   cd rpi-scripts/scripts
   touch my_new_script.sh
   chmod +x my_new_script.sh
   ```

2. **Write Script** (follow template above)

3. **Test Script**
   ```bash
   ./rpi-scripts/cli.sh my_new_script
   ```

4. **Lint & Format**
   ```bash
   shellcheck rpi-scripts/scripts/my_new_script.sh
   shfmt -w rpi-scripts/scripts/my_new_script.sh
   ```

5. **Add Tests**
   - Add test cases to `tests/` or `test_mcp_local.sh`

6. **Document**
   - Add usage comments in script header
   - Update relevant `docs/*.md` if needed

### Modifying Configuration

1. **Edit Defaults**: Modify `rpi-scripts/common_config.sh`
2. **User Overrides**: Edit `rpi-scripts/config.env`
3. **Validate Changes**: Test with `PARROT_DEBUG=true`
4. **Document**: Update `docs/CONFIGURATION.md`

### Debugging Issues

1. **Enable Debug Mode**
   ```bash
   export PARROT_DEBUG=true
   ./rpi-scripts/start_mcp_server.sh
   ```

2. **Check Logs**
   ```bash
   tail -f logs/parrot.log
   grep "ERROR" logs/parrot.log
   ```

3. **Test in Isolation**
   ```bash
   ./rpi-scripts/scripts/problematic_script.sh --verbose
   ```

4. **Use ShellCheck**
   ```bash
   shellcheck rpi-scripts/scripts/problematic_script.sh
   ```

### Running Health Checks

```bash
# Manual health check
./rpi-scripts/cli.sh health_check

# View health check logs
cat logs/health_check.log

# Run with verbose output
PARROT_DEBUG=true ./rpi-scripts/cli.sh health_check
```

---

## AI-Specific Guidance

### When Claude Should Ask Questions

- Unclear requirements or ambiguous user requests
- Security implications of proposed changes
- Changes that affect MCP protocol compliance
- Missing environment variables or configuration
- Hardware-specific assumptions (Raspberry Pi, network devices)
- Whether to add tests vs. modify existing ones
- Breaking changes to existing scripts

### When to Proceed Without Asking

- Adding logging to existing operations
- Fixing obvious bugs with clear solutions
- Formatting/linting changes
- Adding input validation to scripts
- Improving error messages
- Adding comments or documentation
- Following established patterns in the codebase

### Code Review Checklist

Before submitting changes, verify:

- [ ] Script has proper shebang: `#!/usr/bin/env bash`
- [ ] Error handling: `set -euo pipefail` present
- [ ] Sources `common_config.sh` if needed
- [ ] Uses `parrot_*` logging functions with message IDs
- [ ] Input validation for user-supplied data
- [ ] Variables are quoted: `"$var"`
- [ ] Script is executable: `chmod +x`
- [ ] Passes ShellCheck with no errors
- [ ] Formatted with shfmt
- [ ] Tests added or updated
- [ ] Documentation updated if needed
- [ ] No secrets or sensitive data in logs
- [ ] MCP spec compliance maintained

### Common Pitfalls to Avoid

1. **Don't add Node.js/Python dependencies**: This is a pure Bash project
2. **Don't skip input validation**: Security is critical
3. **Don't use `/tmp` for sensitive data**: See `SECURITY.md`
4. **Don't modify MCP message format**: Follow spec exactly
5. **Don't suppress errors with `|| true`**: Handle errors explicitly
6. **Don't use bashisms**: Keep scripts POSIX-compatible where possible
7. **Don't skip logging**: Every operation should be traceable
8. **Don't hardcode paths**: Use configuration variables
9. **Don't add "improvements" beyond requirements**: Keep it simple
10. **Don't commit without testing**: Run tests locally first

---

## Integration with Other AI Assistants

This project includes integration guides for multiple AI assistants:

- **Claude**: This file (`CLAUDE.md`)
- **GitHub Copilot**: `.github/copilot-instructions.md`
- **Google Gemini**: `GEMINI.md`
- **Cursor AI**: `.cursorrules`

All guides emphasize:
- MCP spec compliance
- POSIX Bash portability
- Structured logging
- Security-first development
- Minimal dependencies

---

## Related Documentation

- **Project Overview**: `README.md`
- **Contributing**: `CONTRIBUTING.md`
- **Security**: `SECURITY.md`
- **Configuration**: `docs/CONFIGURATION.md`
- **Logging**: `docs/LOGGING.md`
- **Troubleshooting**: `docs/TROUBLESHOOTING.md`
- **Rate Limiting**: `docs/RATE_LIMITER.md`
- **IPC Security**: `docs/IPC_SECURITY.md`
- **Copilot Guide**: `docs/COPILOT_CODEX_GUIDE.md`

---

## Getting Help

- **GitHub Issues**: Report bugs, request features
- **GitHub Discussions**: Ask questions, share ideas
- **Documentation**: Check `docs/` for detailed guides
- **Logs**: Always check `logs/parrot.log` for debugging

---

## Philosophy & Principles

The Parrot MCP Server follows these core principles:

1. **Spec-First Development**: MCP specification is the source of truth
2. **Transparency Over Cleverness**: Explicit, auditable code
3. **Portability Over Features**: POSIX compliance, minimal dependencies
4. **Security by Design**: Validate everything, trust nothing
5. **Observability by Default**: Log everything with message IDs
6. **Simplicity Over Abstraction**: No premature optimization
7. **Community Over Ego**: Collaboration, feedback, iteration

Every design choice should empower builders while reducing friction. The server should disappear into the workflow, letting developers focus on behavior, not infrastructure.

---

*Last Updated: 2026-01-09*
*Version: 0.x.x (Experimental)*
