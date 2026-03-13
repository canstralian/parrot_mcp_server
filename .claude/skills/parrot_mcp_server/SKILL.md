# parrot_mcp_server Development Patterns

> Auto-generated skill from repository analysis

## Overview

The parrot_mcp_server is a Python-based project that includes a collection of Raspberry Pi management scripts alongside core server functionality. The project focuses heavily on system administration and automation through shell scripts, with an emphasis on reliability, error handling, and maintainability. The codebase follows a hybrid approach combining Python application logic with extensive shell scripting for system-level operations.

## Coding Conventions

### File Naming
- Use `snake_case` for all file names
- Shell scripts in `rpi-scripts/` directory follow descriptive naming patterns
- Example: `system_update.sh`, `setup_cron.sh`, `cli.sh`

### Import Style
```python
# Mixed import patterns are acceptable
import os
from pathlib import Path
import logging as log
```

### Code Organization
- Core Python application files in root directory
- System scripts organized under `rpi-scripts/` with subdirectories
- Shell scripts grouped by functionality in `rpi-scripts/scripts/`

### Commit Messages
- Use freeform style with average length around 48 characters
- Focus on clear, concise descriptions of changes
- No strict prefix requirements

## Workflows

### RPI Script Bug Fixing
**Trigger:** When RPI scripts have bugs, security issues, or functionality failures
**Command:** `/fix-rpi-bugs`

1. **Identify critical/high priority bugs**
   - Review error logs and script execution failures
   - Check for common issues: permission problems, path errors, logic flaws
   
2. **Fix shell script issues systematically**
   ```bash
   # Fix permissions
   chmod +x script_name.sh
   
   # Add proper error handling
   set -e  # Exit on error
   set -u  # Exit on undefined variable
   ```

3. **Update multiple script files simultaneously**
   - Apply consistent fixes across related scripts
   - Ensure all scripts follow same error handling patterns
   
4. **Add safety checks and error handling**
   ```bash
   # Example safety pattern
   if [[ ! -f "$CONFIG_FILE" ]]; then
       echo "Error: Config file not found: $CONFIG_FILE"
       exit 1
   fi
   ```

### RPI Script Enhancement
**Trigger:** When RPI scripts need improved logging, error handling, or features
**Command:** `/enhance-rpi-scripts`

1. **Identify scripts needing enhancement**
   - Review existing functionality gaps
   - Assess logging and monitoring capabilities
   
2. **Add comprehensive logging**
   ```bash
   # Logging pattern
   LOG_FILE="/var/log/script_name.log"
   
   log_message() {
       echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
   }
   
   log_message "Script started"
   ```

3. **Improve error handling and safety checks**
   - Implement robust error detection
   - Add rollback mechanisms where applicable
   - Validate inputs and prerequisites

4. **Make scripts executable and fix paths**
   - Ensure proper file permissions
   - Use absolute paths where necessary
   - Test script portability across environments

## Testing Patterns

### Test File Organization
- Test files follow the `*.test.*` pattern
- Framework detection is flexible to accommodate various testing approaches
- Focus on integration testing for shell scripts

### Testing Shell Scripts
```bash
# Example test pattern for shell scripts
test_script_execution() {
    local output
    output=$(./script_name.sh 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "PASS: Script executed successfully"
    else
        echo "FAIL: Script failed with exit code $exit_code"
        echo "Output: $output"
    fi
}
```

## Commands

| Command | Purpose |
|---------|---------|
| `/fix-rpi-bugs` | Systematically identify and fix critical bugs in RPI shell scripts |
| `/enhance-rpi-scripts` | Improve existing scripts with better logging, error handling, and features |
| `/test-shell-scripts` | Run comprehensive tests on shell script functionality |
| `/update-permissions` | Fix file permissions across all shell scripts |
| `/add-logging` | Implement consistent logging patterns across script files |
| `/validate-paths` | Check and fix path issues in shell scripts |