#!/usr/bin/env bash
# sarif_rules_registry.sh - Central registry for SARIF rule identifiers
# Part of SARIF ABI Contract v0.5 Integrity Baseline
# Provides stable rule IDs and semantic versioning support

set -euo pipefail

# Rule registry with stable IDs and versions
# Format: RULE_ID:VERSION:DESCRIPTION:CATEGORY
declare -A SARIF_RULES=(
    ["SEC001"]="1.0.0:Hardcoded credentials detected:security"
    ["SEC002"]="1.0.0:Insecure random number generation:security"
    ["SEC003"]="1.0.0:Command injection vulnerability:security"
    ["SEC004"]="1.0.0:Path traversal vulnerability:security"
    ["SEC005"]="1.0.0:Insufficient input validation:security"
    ["QUAL001"]="1.0.0:Code complexity exceeds threshold:quality"
    ["QUAL002"]="1.0.0:Duplicated code block detected:quality"
    ["QUAL003"]="1.0.0:Missing error handling:quality"
    ["PERF001"]="1.0.0:Inefficient algorithm usage:performance"
    ["PERF002"]="1.0.0:Excessive resource allocation:performance"
)

# Rule Change Impact Analysis (RCIA) version tracking
# Tracks when rule logic changes to trigger SemVer bumps
declare -A RULE_CHANGE_LOG=(
    ["SEC001"]="1.0.0:2025-11-11:Initial implementation"
    ["SEC002"]="1.0.0:2025-11-11:Initial implementation"
    ["SEC003"]="1.0.0:2025-11-11:Initial implementation"
    ["SEC004"]="1.0.0:2025-11-11:Initial implementation"
    ["SEC005"]="1.0.0:2025-11-11:Initial implementation"
    ["QUAL001"]="1.0.0:2025-11-11:Initial implementation"
    ["QUAL002"]="1.0.0:2025-11-11:Initial implementation"
    ["QUAL003"]="1.0.0:2025-11-11:Initial implementation"
    ["PERF001"]="1.0.0:2025-11-11:Initial implementation"
    ["PERF002"]="1.0.0:2025-11-11:Initial implementation"
)

# Get rule information by ID
get_rule_info() {
    local rule_id="$1"
    if [[ -n "${SARIF_RULES[$rule_id]:-}" ]]; then
        echo "${SARIF_RULES[$rule_id]}"
        return 0
    else
        echo "ERROR:Rule ID '$rule_id' not found in registry" >&2
        return 1
    fi
}

# Get rule version
get_rule_version() {
    local rule_id="$1"
    local info
    info=$(get_rule_info "$rule_id") || return 1
    echo "$info" | cut -d':' -f1
}

# Get rule description
get_rule_description() {
    local rule_id="$1"
    local info
    info=$(get_rule_info "$rule_id") || return 1
    echo "$info" | cut -d':' -f2
}

# Get rule category
get_rule_category() {
    local rule_id="$1"
    local info
    info=$(get_rule_info "$rule_id") || return 1
    echo "$info" | cut -d':' -f3
}

# List all rules
list_rules() {
    echo "Available SARIF Rules:"
    echo "======================"
    for rule_id in "${!SARIF_RULES[@]}"; do
        local version
        local desc
        local category
        version=$(get_rule_version "$rule_id")
        desc=$(get_rule_description "$rule_id")
        category=$(get_rule_category "$rule_id")
        printf "%-10s v%-8s [%-12s] %s\n" "$rule_id" "$version" "$category" "$desc"
    done | sort
}

# Validate rule ID format
validate_rule_id() {
    local rule_id="$1"
    if [[ "$rule_id" =~ ^[A-Z]+[0-9]{3}$ ]]; then
        return 0
    else
        echo "ERROR:Invalid rule ID format. Expected pattern: [A-Z]+[0-9]{3}" >&2
        return 1
    fi
}

# Get RCIA change log entry
get_rule_change_log() {
    local rule_id="$1"
    if [[ -n "${RULE_CHANGE_LOG[$rule_id]:-}" ]]; then
        echo "${RULE_CHANGE_LOG[$rule_id]}"
        return 0
    else
        echo "No change log found for rule '$rule_id'" >&2
        return 1
    fi
}

# Main CLI interface
main() {
    local cmd="${1:-list}"
    shift || true
    
    case "$cmd" in
        list)
            list_rules
            ;;
        get)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 get <rule_id>" >&2
                exit 1
            fi
            get_rule_info "$1"
            ;;
        version)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 version <rule_id>" >&2
                exit 1
            fi
            get_rule_version "$1"
            ;;
        description)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 description <rule_id>" >&2
                exit 1
            fi
            get_rule_description "$1"
            ;;
        category)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 category <rule_id>" >&2
                exit 1
            fi
            get_rule_category "$1"
            ;;
        validate)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 validate <rule_id>" >&2
                exit 1
            fi
            validate_rule_id "$1"
            ;;
        changelog)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 changelog <rule_id>" >&2
                exit 1
            fi
            get_rule_change_log "$1"
            ;;
        *)
            echo "Usage: $0 {list|get|version|description|category|validate|changelog} [rule_id]" >&2
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
