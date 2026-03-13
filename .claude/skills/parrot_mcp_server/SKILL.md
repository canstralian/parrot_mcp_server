# parrot_mcp_server Development Patterns

> Auto-generated skill from repository analysis

## Overview

This skill teaches development patterns for the parrot_mcp_server repository, a Python-based project that manages system scripts and security control plane hooks. The codebase focuses on RPI (Raspberry Pi) script management, security enforcement through hooks, and system maintenance automation.

## Coding Conventions

### File Naming
- Use **snake_case** for all file names
- Script files use `.sh` extension in `rpi-scripts/` directory
- Python files use `.py` extension in `.claude/hooks/` directory

### Import Style
- Mixed import patterns are acceptable
- Group imports logically (standard library, third-party, local)

### Export Style
- Mixed export patterns based on context
- Shell scripts should be executable with proper shebang lines

### Example Structure
```
parrot_mcp_server/
├── rpi-scripts/
│   ├── cli.sh
│   └── scripts/
│       ├── system_update.sh
│       └── setup_cron.sh
└── .claude/
    └── hooks/
        ├── pre_tool_use.py
        ├── post_tool_use.py
        └── stop_gate.py
```

## Workflows

### RPI Scripts Bug Fixing
**Trigger:** When bugs are found in RPI script functionality
**Command:** `/fix-rpi-bugs`

1. **Identify critical/high priority issues**
   - Review error logs and user reports
   - Prioritize script execution failures
   - Focus on CLI and core script functionality

2. **Fix script execution problems**
   - Update shell script logic in `rpi-scripts/cli.sh`
   - Repair broken scripts in `rpi-scripts/scripts/*.sh`
   - Ensure proper exit codes and error handling

3. **Update logging and error handling**
   - Add meaningful error messages
   - Implement proper logging mechanisms
   - Include debug information for troubleshooting

4. **Test script functionality**
   - Verify scripts execute without errors
   - Test edge cases and error conditions
   - Validate on target RPI environment

### Security Hooks Maintenance
**Trigger:** When security hooks need updates or documentation
**Command:** `/update-security-hooks`

1. **Update hook implementations**
   - Modify security logic in hook files
   - Ensure proper integration with control plane
   - Maintain backward compatibility

2. **Add or improve docstrings**
   ```python
   def pre_tool_use():
       """
       Pre-execution security validation hook.
       
       Validates tool usage before execution to ensure
       security compliance and authorization.
       """
   ```

3. **Maintain security enforcement logic**
   - Update validation rules in `pre_tool_use.py`
   - Enhance monitoring in `post_tool_use.py`
   - Refine stop conditions in `stop_gate.py`

### System Script Enhancement
**Trigger:** When system scripts need improved functionality
**Command:** `/enhance-system-scripts`

1. **Add comprehensive logging**
   ```bash
   #!/bin/bash
   LOG_FILE="/var/log/system_update.log"
   
   log_info() {
       echo "$(date): INFO: $1" | tee -a "$LOG_FILE"
   }
   
   log_error() {
       echo "$(date): ERROR: $1" | tee -a "$LOG_FILE"
   }
   ```

2. **Improve error handling**
   - Add proper exit codes for different failure scenarios
   - Implement retry logic where appropriate
   - Graceful degradation for non-critical failures

3. **Add permission checks**
   ```bash
   if [ "$EUID" -ne 0 ]; then
       log_error "This script must be run as root"
       exit 1
   fi
   ```

4. **Test reliability improvements**
   - Verify scripts handle edge cases
   - Test with various system states
   - Validate logging output and error reporting

## Testing Patterns

- Test files follow the pattern `*.test.*`
- Testing framework is not explicitly configured
- Focus on functional testing of shell scripts
- Validate security hook behavior with mock scenarios

## Commands

| Command | Purpose |
|---------|---------|
| `/fix-rpi-bugs` | Fix critical bugs and improve functionality in RPI scripts |
| `/update-security-hooks` | Maintain and document security control plane hooks |
| `/enhance-system-scripts` | Enhance system maintenance scripts with better logging and reliability |