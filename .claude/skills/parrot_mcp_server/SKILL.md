# parrot_mcp_server Development Patterns

> Auto-generated skill from repository analysis

## Overview

The `parrot_mcp_server` is a Python-based MCP (Model Context Protocol) server project that emphasizes documentation maintenance, shell script automation, and GitHub Actions security best practices. The codebase follows iterative development patterns with frequent documentation updates and proactive security configurations.

## Coding Conventions

### File Naming
- Use `snake_case` for all Python files and directories
- Example: `parrot_server.py`, `common_config.sh`, `test_mcp_local.sh`

### Import Style
The project uses mixed import styles depending on context:
```python
# Standard library imports
import os
import sys

# Third-party imports
from some_package import module

# Local imports
from .local_module import function
```

### Export Style
Mixed export patterns are used based on module requirements and API design needs.

### Commit Messages
- Freeform style with average length of 49 characters
- Focus on clarity and brevity
- Common patterns: "Fix [issue]", "Update [component]", "Add [feature]"

## Workflows

### GitHub Workflow Permissions Fix
**Trigger:** When code scanning alerts appear for missing workflow permissions
**Command:** `/fix-workflow-permissions`

1. Navigate to the `.github/workflows/` directory
2. Identify the workflow file triggering security alerts
3. Add a `permissions` section at the top level of the workflow:
   ```yaml
   permissions:
     contents: read
     security-events: read
   ```
4. Set permissions to read-only by default for security
5. Create a pull request with the changes
6. Merge after review to resolve security alerts

### Copilot Codex Guide Updates
**Trigger:** When refining AI assistant configuration or addressing schema issues
**Command:** `/update-codex-guide`

1. Open `docs/COPILOT_CODEX_GUIDE.md`
2. Identify the section requiring updates (configuration, schema, examples)
3. Make incremental changes in small, focused commits
4. Test any code examples or configurations mentioned
5. Create multiple commits for different aspects of the update
6. Submit pull request with comprehensive description of changes
7. Review and merge to keep AI assistant documentation current

### README Documentation Updates
**Trigger:** When project information needs updating or enhancement
**Command:** `/update-readme`

1. Review current `README.md` content for accuracy
2. Identify sections needing updates:
   - Installation instructions
   - Usage examples
   - Configuration details
   - API documentation
3. Make targeted changes to specific sections
4. Ensure all code examples are tested and working
5. Commit changes with descriptive message
6. Either merge directly or create PR based on change scope

### Log File Cleanup
**Trigger:** When log files are inadvertently added to version control
**Command:** `/cleanup-logs`

1. Identify committed log files:
   ```bash
   git ls-files | grep -E "\.(log|out)$"
   ```
2. Remove files from git tracking:
   ```bash
   git rm --cached logs/parrot.log
   git rm --cached rpi-scripts/logs/parrot.log
   ```
3. Update `.gitignore` to prevent future commits:
   ```gitignore
   # Log files
   *.log
   logs/
   rpi-scripts/logs/
   ```
4. Commit the removal and `.gitignore` updates
5. Verify logs are no longer tracked in future commits

### Script Configuration Updates
**Trigger:** When fixing shell script issues or improving configuration management
**Command:** `/update-script-config`

1. Identify the configuration issue in `rpi-scripts/common_config.sh`
2. Make necessary changes to environment variables or paths:
   ```bash
   # Example configuration pattern
   export MCP_SERVER_HOST="localhost"
   export MCP_SERVER_PORT="8080"
   ```
3. Update corresponding test file `rpi-scripts/test_mcp_local.sh`
4. Run BATS tests to verify changes:
   ```bash
   bats rpi-scripts/tests/*.bats
   ```
5. Fix any failing tests in the `rpi-scripts/tests/` directory
6. Commit configuration and test changes together
7. Test deployment to ensure scripts work in target environment

## Testing Patterns

The project uses BATS (Bash Automated Testing System) for shell script testing:

### Test File Structure
- Test files follow the pattern: `*.bats` in `rpi-scripts/tests/`
- Tests validate script functionality and configuration

### Test Example Pattern
```bash
#!/usr/bin/env bats

@test "MCP server configuration is valid" {
  source rpi-scripts/common_config.sh
  [ -n "$MCP_SERVER_HOST" ]
  [ -n "$MCP_SERVER_PORT" ]
}
```

## Commands

| Command | Purpose |
|---------|---------|
| `/fix-workflow-permissions` | Add security permissions to GitHub Actions workflows |
| `/update-codex-guide` | Iteratively update AI assistant configuration documentation |
| `/update-readme` | Maintain and enhance project README documentation |
| `/cleanup-logs` | Remove accidentally committed log files and update .gitignore |
| `/update-script-config` | Modify shell script configurations and run associated tests |