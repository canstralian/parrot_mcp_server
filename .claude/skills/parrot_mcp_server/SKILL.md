# parrot_mcp_server Development Patterns

> Auto-generated skill from repository analysis

## Overview

The parrot_mcp_server is a Python-based MCP (Model Context Protocol) server that appears to facilitate AI assistant integrations. This codebase follows a structured approach with shell scripts for Raspberry Pi deployment, comprehensive testing using BATS (Bash Automated Testing System), and extensive documentation. The project emphasizes iterative development, security best practices, and proper CI/CD workflows.

## Coding Conventions

### File Naming
- Use `snake_case` for all files and directories
- Shell scripts use `.sh` extension
- Test files follow pattern `*.bats` for BATS tests
- Documentation uses `.md` extension

### Directory Structure
```
├── rpi-scripts/           # Raspberry Pi deployment scripts
│   ├── tests/            # BATS test files
│   ├── scripts/          # Example and utility scripts
│   └── logs/             # Log files (gitignored)
├── docs/                 # Documentation
└── .github/workflows/    # CI/CD workflows
```

### Import/Export Style
- Mixed import style depending on context
- Shell scripts use common configuration pattern:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"
```

### Commit Style
- Freeform commit messages (average 49 characters)
- No strict prefixes, but descriptive and concise
- Co-authored commits when pair programming

## Workflows

### GitHub Workflow Permissions Fix
**Trigger:** When code scanning alerts are raised for missing permissions in workflows
**Command:** `/fix-workflow-permissions`

1. Identify the workflow file with missing permissions in `.github/workflows/`
2. Add a permissions block to the workflow YAML:
```yaml
permissions:
  contents: read
  security-events: write
```
3. Commit with an alert autofix message referencing the security issue
4. Verify the alert is resolved in GitHub Security tab

### Documentation Update
**Trigger:** When documentation needs updating or expanding
**Command:** `/update-docs`

1. Identify the documentation file that needs updates (`README.md`, `docs/*.md`, `CONTRIBUTING.md`)
2. Make content changes ensuring:
   - Clear, concise language
   - Proper markdown formatting
   - Updated examples and code snippets
3. Commit with descriptive message indicating what was updated
4. Review rendered documentation for formatting issues

### Log File Management
**Trigger:** When log files are accidentally tracked or need to be excluded
**Command:** `/fix-log-tracking`

1. Update `.gitignore` to exclude log patterns:
```gitignore
*.log
logs/
rpi-scripts/logs/
```
2. Remove existing log files from git tracking:
```bash
git rm --cached logs/parrot.log rpi-scripts/logs/parrot.log
```
3. Ensure logs directory structure is maintained with `.gitkeep` if needed
4. Commit changes with clear message about log file handling

### Copilot Guide Iteration
**Trigger:** When refining AI coding assistant configuration documentation
**Command:** `/update-copilot-guide`

1. Open `docs/COPILOT_CODEX_GUIDE.md`
2. Make small, focused improvements:
   - Add new configuration options
   - Clarify existing instructions
   - Update examples with current syntax
3. Commit with co-authored attribution if pair programming:
```
Update Copilot configuration guide

Co-authored-by: Name <email@example.com>
```
4. Repeat process for iterative refinements in the same session

### Script Path Fix
**Trigger:** When shell scripts fail due to incorrect path assumptions
**Command:** `/fix-script-paths`

1. Add `SCRIPT_DIR` variable at the top of shell scripts:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
2. Update hardcoded relative paths to use `SCRIPT_DIR`:
```bash
# Before
source ./common_config.sh

# After  
source "${SCRIPT_DIR}/common_config.sh"
```
3. Test script execution from different directories to ensure paths work correctly
4. Apply changes to related scripts (`test_mcp_local.sh`, `start_mcp_server.sh`)

### Feature Implementation with Testing
**Trigger:** When adding new functionality to the system
**Command:** `/implement-feature`

1. Implement core functionality in appropriate files:
   - Add configuration to `rpi-scripts/common_config.sh`
   - Create main implementation files
2. Add comprehensive BATS tests in `rpi-scripts/tests/`:
```bash
#!/usr/bin/env bats

@test "feature functionality works correctly" {
    run ./script_under_test.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "expected_output" ]]
}
```
3. Create documentation in `docs/` explaining the feature
4. Add example usage scripts in `rpi-scripts/scripts/example_*.sh`
5. Test the complete workflow before committing

## Testing Patterns

### BATS Testing Framework
- Tests are written in `rpi-scripts/tests/*.bats`
- Use descriptive test names with `@test "description"`
- Assert exit codes with `[ "$status" -eq 0 ]`
- Check output patterns with `[[ "$output" =~ "pattern" ]]`
- Run commands with `run command` for better error handling

### Test Structure Example
```bash
#!/usr/bin/env bats

setup() {
    # Common setup for all tests
    export TEST_VAR="value"
}

@test "script executes successfully" {
    run ./target_script.sh
    [ "$status" -eq 0 ]
}

@test "script produces expected output" {
    run ./target_script.sh
    [[ "$output" =~ "Success" ]]
}
```

## Commands

| Command | Purpose |
|---------|---------|
| `/fix-workflow-permissions` | Add permissions configuration to GitHub Actions workflows |
| `/update-docs` | Update project documentation with new content or corrections |
| `/fix-log-tracking` | Handle log files in git tracking and update gitignore |
| `/update-copilot-guide` | Iteratively update AI assistant configuration documentation |
| `/fix-script-paths` | Fix relative path references in shell scripts |
| `/implement-feature` | Implement new features with comprehensive testing and documentation |