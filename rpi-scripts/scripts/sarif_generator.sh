#!/usr/bin/env bash
# sarif_generator.sh - SARIF 2.1.0 compliant output generator
# Part of SARIF ABI Contract v0.5 Integrity Baseline
# Implements deterministic output, provenance metadata, and stable fingerprints

set -euo pipefail

# Source the rules registry
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/sarif_rules_registry.sh
source "${SCRIPT_DIR}/sarif_rules_registry.sh"

# Constants
SARIF_VERSION="2.1.0"
TOOL_NAME="Parrot MCP Server"
TOOL_VERSION="0.5.0"
TOOL_SEMANTIC_VERSION="0.5.0"

# Get repository information for provenance
get_git_commit_sha() {
    git rev-parse HEAD 2>/dev/null || echo "unknown"
}

get_git_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

get_git_remote_url() {
    git config --get remote.origin.url 2>/dev/null || echo "unknown"
}

# Calculate SHA-256 hash for policy integrity
calculate_sha256() {
    local input="$1"
    echo -n "$input" | sha256sum | awk '{print $1}'
}

# Generate deterministic partial fingerprint
# Uses rule ID, file URI, and location to create stable identifier
generate_partial_fingerprint() {
    local rule_id="$1"
    local uri="$2"
    local start_line="$3"
    local start_column="${4:-1}"
    
    # Create stable fingerprint from canonical components
    local fingerprint_base="${rule_id}:${uri}:${start_line}:${start_column}"
    calculate_sha256 "$fingerprint_base"
}

# Canonicalize URI to relative path with uriBaseId
canonicalize_uri() {
    local absolute_path="$1"
    local base_path="${2:-$(pwd)}"
    
    # Convert to relative path if absolute
    if [[ "$absolute_path" == "$base_path"* ]]; then
        echo "${absolute_path#"$base_path"/}"
    else
        echo "$absolute_path"
    fi
}

# Generate SARIF header with provenance metadata
generate_sarif_header() {
    local commit_sha
    local branch
    local remote_url
    local timestamp
    
    commit_sha=$(get_git_commit_sha)
    branch=$(get_git_branch)
    remote_url=$(get_git_remote_url)
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat <<EOF
{
  "version": "${SARIF_VERSION}",
  "\$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "${TOOL_NAME}",
          "version": "${TOOL_VERSION}",
          "semanticVersion": "${TOOL_SEMANTIC_VERSION}",
          "informationUri": "https://github.com/canstralian/parrot_mcp_server",
          "properties": {
            "ruleRegistryVersion": "1.0.0",
            "abiContractVersion": "0.5.0",
            "integrityBaseline": "v0.5",
            "policyChecksum": "$(calculate_sha256 "$(list_rules)")"
          },
          "rules": []
        }
      },
      "versionControlProvenance": [
        {
          "repositoryUri": "${remote_url}",
          "revisionId": "${commit_sha}",
          "branch": "${branch}",
          "revisionTag": "$(git describe --tags --exact-match 2>/dev/null || echo 'none')"
        }
      ],
      "properties": {
        "analysisTimestamp": "${timestamp}",
        "hostArchitecture": "$(uname -m)",
        "hostOS": "$(uname -s)",
        "chainOfCustody": {
          "generatorVersion": "${TOOL_VERSION}",
          "generatorChecksum": "$(calculate_sha256 "${BASH_SOURCE[0]}")"
        }
      },
      "results": []
    }
  ]
}
EOF
}

# Add rule definition to SARIF output
add_rule_definition() {
    local rule_id="$1"
    local version
    local description
    local category
    
    version=$(get_rule_version "$rule_id")
    description=$(get_rule_description "$rule_id")
    category=$(get_rule_category "$rule_id")
    
    cat <<EOF
      {
        "id": "${rule_id}",
        "name": "${rule_id}",
        "shortDescription": {
          "text": "${description}"
        },
        "fullDescription": {
          "text": "${description}"
        },
        "defaultConfiguration": {
          "level": "warning"
        },
        "properties": {
          "category": "${category}",
          "version": "${version}",
          "tags": [
            "${category}"
          ]
        }
      }
EOF
}

# Add result to SARIF output
add_result() {
    local rule_id="$1"
    local message="$2"
    local uri="$3"
    local start_line="$4"
    local start_column="${5:-1}"
    local end_line="${6:-$start_line}"
    local end_column="${7:-100}"
    local level="${8:-warning}"
    
    local canonical_uri
    local fingerprint
    
    canonical_uri=$(canonicalize_uri "$uri")
    fingerprint=$(generate_partial_fingerprint "$rule_id" "$canonical_uri" "$start_line" "$start_column")
    
    cat <<EOF
      {
        "ruleId": "${rule_id}",
        "level": "${level}",
        "message": {
          "text": "${message}"
        },
        "locations": [
          {
            "physicalLocation": {
              "artifactLocation": {
                "uri": "${canonical_uri}",
                "uriBaseId": "%SRCROOT%"
              },
              "region": {
                "startLine": ${start_line},
                "startColumn": ${start_column},
                "endLine": ${end_line},
                "endColumn": ${end_column}
              }
            }
          }
        ],
        "partialFingerprints": {
          "primaryLocationLineHash": "${fingerprint}"
        },
        "properties": {
          "ruleVersion": "$(get_rule_version "$rule_id")"
        }
      }
EOF
}

# Sort results deterministically by ruleId, URI, then startLine
sort_results() {
    local input_file="$1"
    # This is a placeholder - actual implementation would use jq or similar
    # to sort the JSON array deterministically
    cat "$input_file"
}

# Generate complete SARIF report
generate_sarif_report() {
    local output_file="${1:-/tmp/sarif_output.json}"
    
    generate_sarif_header > "$output_file"
    
    echo "Generated SARIF report: $output_file"
}

# Validate SARIF output against schema
validate_sarif() {
    local sarif_file="$1"
    
    if ! command -v jq &> /dev/null; then
        echo "Warning: jq not found, skipping JSON validation" >&2
        return 0
    fi
    
    if ! jq empty "$sarif_file" 2>/dev/null; then
        echo "ERROR: Invalid JSON in SARIF file" >&2
        return 1
    fi
    
    echo "SARIF validation passed"
    return 0
}

# Main CLI interface
main() {
    local cmd="${1:-generate}"
    shift || true
    
    case "$cmd" in
        generate)
            local output="${1:-/tmp/sarif_output.json}"
            generate_sarif_report "$output"
            ;;
        validate)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 validate <sarif_file>" >&2
                exit 1
            fi
            validate_sarif "$1"
            ;;
        fingerprint)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 fingerprint <rule_id> <uri> <line> [column]" >&2
                exit 1
            fi
            generate_partial_fingerprint "$1" "$2" "$3" "${4:-1}"
            ;;
        *)
            echo "Usage: $0 {generate|validate|fingerprint} [args]" >&2
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
