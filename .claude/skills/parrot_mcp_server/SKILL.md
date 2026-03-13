# parrot_mcp_server Development Patterns

> Auto-generated skill from repository analysis

## Overview

The parrot_mcp_server is a Python-based MCP (Model Context Protocol) server that appears to be designed for Raspberry Pi environments. This codebase follows collaborative AI development practices with frequent iterative improvements, comprehensive documentation, and shell script automation for system management.

## Coding Conventions

### File Naming
- **Python files**: Use `snake_case` naming convention
- **Documentation**: Use `UPPER_CASE.md` for important docs, `lower_case.md` for others
- **Scripts**: Use descriptive names with `.sh` extension

### Import Style
```python
# Mixed import style - both absolute and relative imports
from parrot_mcp_server import module
import os
import sys
```

### Project Structure
```
parrot_mcp_server/
├── src/parrot_mcp_server/     # Main Python package
├── rpi-scripts/               # Raspberry Pi shell scripts
├── docs/                      # Documentation files
├── logs/                      # Log files
└── .github/workflows/         # CI/CD workflows
```

## Workflows

### Documentation Iterative Refinement
**Trigger:** When improving documentation clarity and completeness  
**Command:** `/refine-docs`

1. Create initial documentation draft
2. Make multiple small iterative commits refining content
3. Use AI collaboration to improve clarity and completeness
4. Focus on files like `docs/COPILOT_CODEX_GUIDE.md` and `README.md`
5. Submit final version via pull request

```bash
# Typical commit pattern
git add docs/
git commit -m "Refine documentation for clarity"
```

### GitHub Actions Security Fix
**Trigger:** When code scanning alerts identify missing permissions in workflows  
**Command:** `/fix-workflow-permissions`

1. Create autofix branch from security alert
2. Add permissions configuration to affected workflows
3. Update `.github/workflows/*.yml` files with proper permissions:
   ```yaml
   permissions:
     contents: read
     security-events: write
   ```
4. Test workflow changes
5. Merge via pull request

### Script Bug Fix with Logging
**Trigger:** When shell scripts have bugs or shellcheck warnings  
**Command:** `/fix-shell-script`

1. Identify issue through logs or testing failures
2. Fix script with proper error handling:
   ```bash
   #!/bin/bash
   set -euo pipefail
   source "$(dirname "$0")/common_config.sh"
   ```
3. Update logging configuration in `logs/parrot.log`
4. Add or update corresponding `.bats` test files
5. Verify fixes with shellcheck
6. Merge via pull request

### Feature Implementation with Documentation
**Trigger:** When adding new system components or capabilities  
**Command:** `/new-feature`

1. Create implementation files in `src/parrot_mcp_server/`
2. Add configuration support (update `params.json` if needed)
3. Write comprehensive documentation in `docs/`
4. Add corresponding tests in `rpi-scripts/tests/*.bats`
5. Update project metadata and configuration files
6. Ensure all changes are documented and tested

### AI Collaborative Development
**Trigger:** When implementing features or fixes with AI assistance  
**Command:** `/ai-collab`

1. Co-author commits with AI bots using proper attribution
2. Implement changes following AI guidance and suggestions
3. Sign-off commits with both human and AI contributors
4. Ensure code quality through collaborative review
5. Merge via pull request with comprehensive change descriptions

## Testing Patterns

### Shell Script Testing
- Use **BATS** (Bash Automated Testing System) for shell script tests
- Test files located in `rpi-scripts/tests/*.bats`
- Include comprehensive logging verification

### Python Testing
- Test files follow pattern `*.test.*`
- Framework appears to be custom or minimal setup
- Focus on integration testing with system components

## Commands

| Command | Purpose |
|---------|---------|
| `/refine-docs` | Iteratively improve documentation with AI assistance |
| `/fix-workflow-permissions` | Add security permissions to GitHub Actions workflows |
| `/fix-shell-script` | Fix shell script bugs with proper error handling and logging |
| `/new-feature` | Implement new features with full documentation and testing |
| `/ai-collab` | Collaborative development session with AI assistance |