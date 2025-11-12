#!/usr/bin/env bash
# sarif.sh - Unified CLI for SARIF ABI Contract tools
# Author: Canstralian
# Part of SARIF ABI Contract v0.5 Integrity Baseline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat <<EOF
SARIF ABI Contract CLI - Security Analysis for Shell Scripts

Usage: $(basename "$0") <command> [options]

Commands:
  scan <dir> <output>       Scan directory for security issues
  file <file> <output>      Scan single file
  validate <sarif_file>     Validate SARIF output
  rules [list|get|info]     Manage rule registry
  generate <output>         Generate empty SARIF template
  help                      Show this help message

Examples:
  # Scan all scripts in a directory
  $(basename "$0") scan ./scripts output.sarif
  
  # Scan a single file
  $(basename "$0") file myScript.sh findings.sarif
  
  # Validate SARIF output
  $(basename "$0") validate output.sarif
  
  # List all available rules
  $(basename "$0") rules list
  
  # Get rule information
  $(basename "$0") rules get SEC001

For more detailed documentation, see:
  docs/SARIF_ABI_CONTRACT.md
  docs/SARIF_USAGE_EXAMPLES.md

EOF
}

# Main command dispatcher
main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        scan)
            if [[ $# -lt 2 ]]; then
                echo "Error: 'scan' requires <directory> <output_file>" >&2
                echo "Usage: $(basename "$0") scan <directory> <output_file> [pattern]" >&2
                exit 1
            fi
            exec "${SCRIPT_DIR}/sarif_scanner.sh" scan "$@"
            ;;
        
        file)
            if [[ $# -lt 2 ]]; then
                echo "Error: 'file' requires <file> <output_file>" >&2
                echo "Usage: $(basename "$0") file <file> <output_file>" >&2
                exit 1
            fi
            exec "${SCRIPT_DIR}/sarif_scanner.sh" file "$@"
            ;;
        
        validate)
            if [[ $# -lt 1 ]]; then
                echo "Error: 'validate' requires <sarif_file>" >&2
                echo "Usage: $(basename "$0") validate <sarif_file>" >&2
                exit 1
            fi
            exec "${SCRIPT_DIR}/sarif_validator.sh" validate "$@"
            ;;
        
        rules)
            exec "${SCRIPT_DIR}/sarif_rules_registry.sh" "$@"
            ;;
        
        generate)
            if [[ $# -lt 1 ]]; then
                echo "Error: 'generate' requires <output_file>" >&2
                echo "Usage: $(basename "$0") generate <output_file>" >&2
                exit 1
            fi
            exec "${SCRIPT_DIR}/sarif_generator.sh" generate "$@"
            ;;
        
        help|--help|-h)
            show_usage
            exit 0
            ;;
        
        *)
            echo "Error: Unknown command '$cmd'" >&2
            echo "" >&2
            show_usage
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
