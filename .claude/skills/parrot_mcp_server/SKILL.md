```markdown
# parrot_mcp_server Development Patterns

> Auto-generated skill from repository analysis

## Overview

The parrot_mcp_server is a Python-based MCP (Model Context Protocol) server with accompanying shell scripts for Raspberry Pi deployment. This codebase follows iterative development patterns with strong emphasis on security hardening, documentation maintenance, and cross-platform compatibility. The project combines Python server logic with bash automation scripts for embedded deployment scenarios.

## Coding Conventions

### File Naming
- Use **snake_case** for all files: `common_config.sh`, `test_mcp_local.sh`
- Test files follow pattern: `*.test.*`
- Documentation files: `*.md` in docs directory and root

### Import/Export Style
- Mixed approach depending on context
- Shell scripts use consistent sourcing patterns
- Python imports follow standard conventions

### Commit Messages
- Freeform style, average 49 characters
- Descriptive and context-aware
- Often include attribution for automated fixes

### Directory Structure
```
├── docs/                    # Documentation files
├── rpi-scripts/            # Raspberry Pi deployment scripts
│   ├── scripts/            # Individual script modules  
│   ├── logs/              # Log files
│   └── config.env.example # Configuration templates
├── .github/workflows/      # CI/CD workflows
└── logs/                  # Application logs
```

## Workflows

### Documentation Update
**Trigger:** When improving documentation or adding new guides
**Command:** `/update-docs`

1. Identify documentation file to update (`docs/*.md`, `README.md`, etc.)
2. Make incremental, focused changes to improve clarity
3. Commit with descriptive message explaining the improvement
4. Review and make additional refinements if needed
5. Repeat process for iterative enhancement

```bash
# Example workflow
git add docs/api-guide.md
git commit -m "Improve API documentation with usage examples"
```

### GitHub Actions Security Fix
**Trigger:** When security scanning alerts identify missing permissions in workflows
**Command:** `/fix-workflow-permissions`

1. Identify the workflow file triggering security alerts
2. Add appropriate permissions section to the workflow YAML
3. Specify minimal required permissions (contents: read, etc.)
4. Commit with autofix attribution in message
5. Create pull request for review and merge

```yaml
# Example fix
name: CI
on: [push, pull_request]
permissions:
  contents: read
  security-events: write
jobs:
  # ... rest of workflow
```

### Shell Script Security Hardening
**Trigger:** When security vulnerabilities are found in bash scripts
**Command:** `/harden-scripts`

1. Identify vulnerable scripts in `rpi-scripts/` directory
2. Add input validation and sanitization
3. Fix path traversal issues with proper path resolution
4. Add comprehensive error handling with exit codes
5. Update configuration loading to use secure methods
6. Test changes in isolated environment

```bash
# Example hardening patterns
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Secure path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Input validation
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found" >&2
    exit 1
fi
```

### Test Script Path Fixes
**Trigger:** When test scripts fail due to relative path issues in CI/CD
**Command:** `/fix-test-paths`

1. Identify the failing test script (commonly `test_mcp_local.sh`)
2. Add dynamic `SCRIPT_DIR` variable for context-aware path resolution
3. Convert all relative paths to absolute references using `SCRIPT_DIR`
4. Test execution in both local development and CI environments
5. Verify cross-platform compatibility

```bash
# Example path fix
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Before (brittle)
source ./common_config.sh

# After (robust)
source "${SCRIPT_DIR}/common_config.sh"
```

### Configuration and Logging Updates
**Trigger:** When refactoring configuration management or logging systems
**Command:** `/update-config`

1. Update `rpi-scripts/common_config.sh` with new configuration patterns
2. Modify logging functions to improve output format and destinations
3. Create or update `config.env.example` with new configuration options
4. Update dependent scripts to use new configuration methods
5. Ensure logging works across different execution contexts

```bash
# Example configuration pattern
load_config() {
    local config_file="${1:-${SCRIPT_DIR}/config.env}"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        echo "Warning: Config file $config_file not found, using defaults"
    fi
}
```

## Testing Patterns

- Tests are executed via shell scripts with `.sh` extension
- Test files may follow `*.test.*` naming pattern
- Path resolution is critical for CI/CD compatibility
- Tests should work in both local and automated environments
- Error handling and exit codes are important for automation

## Commands

| Command | Purpose |
|---------|---------|
| `/update-docs` | Iteratively improve documentation files with focused changes |
| `/fix-workflow-permissions` | Add security permissions to GitHub Actions workflows |
| `/harden-scripts` | Apply security fixes and validation to shell scripts |
| `/fix-test-paths` | Resolve path issues in test scripts for CI/CD compatibility |
| `/update-config` | Refactor configuration and logging systems |
```