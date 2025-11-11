#!/usr/bin/env bash
# sarif_scanner.sh - Static analysis scanner for shell scripts
# Part of SARIF ABI Contract v0.5 Integrity Baseline
# Scans shell scripts and generates SARIF reports with findings

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/sarif_rules_registry.sh
source "${SCRIPT_DIR}/sarif_rules_registry.sh"

# Temporary storage for findings
declare -a FINDINGS=()

# Scan a shell script for security issues
scan_file() {
    local file="$1"
    local line_num=1
    
    while IFS= read -r line; do
        # SEC001: Hardcoded credentials
        if [[ "$line" =~ (password|passwd|pwd|secret|token|api_key|apikey)[[:space:]]*=[[:space:]]*[\"\']{1}[^\"\']+[\"\']{1} ]]; then
            add_finding "SEC001" "$file" "$line_num" "Potential hardcoded credential detected" "error"
        fi
        
        # SEC002: Insecure random number generation
        if [[ "$line" =~ \$RANDOM ]]; then
            add_finding "SEC002" "$file" "$line_num" "Use of \$RANDOM for security-sensitive operations is not cryptographically secure" "warning"
        fi
        
        # SEC003: Command injection vulnerability
        if [[ "$line" =~ eval[[:space:]]+ ]] || [[ "$line" =~ \$\([^\)]*\$[^\)]*\) ]]; then
            add_finding "SEC003" "$file" "$line_num" "Potential command injection via eval or unquoted variable expansion" "warning"
        fi
        
        # SEC004: Path traversal
        if [[ "$line" =~ \.\./\.\. ]] || [[ "$line" =~ (cat|read|source)[[:space:]]+\$[A-Za-z_]+ ]]; then
            add_finding "SEC004" "$file" "$line_num" "Potential path traversal vulnerability with user input" "warning"
        fi
        
        # SEC005: Insufficient input validation
        if [[ "$line" =~ (rm|mv)[[:space:]]+-[rf]+[[:space:]]+\$ ]] && [[ ! "$line" =~ \[\[.*\]\] ]]; then
            add_finding "SEC005" "$file" "$line_num" "Dangerous command with insufficient input validation" "error"
        fi
        
        # QUAL003: Missing error handling
        if [[ "$line" =~ ^[[:space:]]*(curl|wget|git|ssh)[[:space:]] ]] && [[ ! "$line" =~ \|\| ]] && [[ ! "$line" =~ set[[:space:]]+-e ]]; then
            add_finding "QUAL003" "$file" "$line_num" "External command without error handling" "note"
        fi
        
        ((line_num++))
    done < "$file"
}

# Add a finding to the results
add_finding() {
    local rule_id="$1"
    local file="$2"
    local line="$3"
    local message="$4"
    local level="${5:-warning}"
    
    FINDINGS+=("${rule_id}|${file}|${line}|${message}|${level}")
}

# Generate SARIF output from findings
generate_sarif_output() {
    local output_file="$1"
    local base_dir="${2:-$(pwd)}"
    
    # Start with header
    local commit_sha
    local branch
    local remote_url
    local timestamp
    
    commit_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "unknown")
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Collect unique rule IDs
    local -A used_rules=()
    for finding in "${FINDINGS[@]}"; do
        local rule_id
        rule_id=$(echo "$finding" | cut -d'|' -f1)
        used_rules["$rule_id"]=1
    done
    
    # Start JSON output
    cat > "$output_file" <<EOF
{
  "version": "2.1.0",
  "\$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "Parrot MCP Server",
          "version": "0.5.0",
          "semanticVersion": "0.5.0",
          "informationUri": "https://github.com/canstralian/parrot_mcp_server",
          "properties": {
            "ruleRegistryVersion": "1.0.0",
            "abiContractVersion": "0.5.0",
            "integrityBaseline": "v0.5"
          },
          "rules": [
EOF
    
    # Add rule definitions
    local first_rule=true
    for rule_id in "${!used_rules[@]}"; do
        if [[ "$first_rule" == true ]]; then
            first_rule=false
        else
            echo "," >> "$output_file"
        fi
        
        local version
        local description
        local category
        version=$(get_rule_version "$rule_id")
        description=$(get_rule_description "$rule_id")
        category=$(get_rule_category "$rule_id")
        
        cat >> "$output_file" <<EOF
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
                "tags": ["${category}"]
              }
            }
EOF
    done
    
    # Close rules array and add provenance
    cat >> "$output_file" <<EOF

          ]
        }
      },
      "versionControlProvenance": [
        {
          "repositoryUri": "${remote_url}",
          "revisionId": "${commit_sha}",
          "branch": "${branch}"
        }
      ],
      "properties": {
        "analysisTimestamp": "${timestamp}",
        "hostArchitecture": "$(uname -m)",
        "hostOS": "$(uname -s)"
      },
      "results": [
EOF
    
    # Sort findings deterministically by rule_id, file, line
    local sorted_findings
    sorted_findings=$(printf '%s\n' "${FINDINGS[@]}" | sort -t'|' -k1,1 -k2,2 -k3,3n)
    
    # Add results
    local first_result=true
    while IFS='|' read -r rule_id file line message level; do
        if [[ "$first_result" == true ]]; then
            first_result=false
        else
            echo "," >> "$output_file"
        fi
        
        # Canonicalize file path
        local rel_path
        if [[ "$file" == "$base_dir"* ]]; then
            rel_path="${file#"$base_dir"/}"
        else
            rel_path="$file"
        fi
        
        # Generate fingerprint
        local fingerprint
        fingerprint=$(echo -n "${rule_id}:${rel_path}:${line}" | sha256sum | awk '{print $1}')
        
        local rule_version
        rule_version=$(get_rule_version "$rule_id")
        
        cat >> "$output_file" <<EOF
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
                  "uri": "${rel_path}",
                  "uriBaseId": "%SRCROOT%"
                },
                "region": {
                  "startLine": ${line}
                }
              }
            }
          ],
          "partialFingerprints": {
            "primaryLocationLineHash": "${fingerprint}"
          },
          "properties": {
            "ruleVersion": "${rule_version}"
          }
        }
EOF
    done <<< "$sorted_findings"
    
    # Close JSON
    cat >> "$output_file" <<EOF

      ]
    }
  ]
}
EOF
}

# Scan directory recursively
scan_directory() {
    local dir="$1"
    local pattern="${2:-*.sh}"
    
    echo "Scanning directory: $dir" >&2
    
    while IFS= read -r -d '' file; do
        echo "  Analyzing: $file" >&2
        scan_file "$file"
    done < <(find "$dir" -type f -name "$pattern" -print0)
    
    echo "Found ${#FINDINGS[@]} issue(s)" >&2
}

# Main CLI interface
main() {
    local cmd="${1:-scan}"
    shift || true
    
    case "$cmd" in
        scan)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 scan <directory> <output_file> [pattern]" >&2
                exit 1
            fi
            
            local dir="$1"
            local output="$2"
            local pattern="${3:-*.sh}"
            
            scan_directory "$dir" "$pattern"
            generate_sarif_output "$output" "$dir"
            
            echo "SARIF report generated: $output" >&2
            ;;
        file)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 file <file> <output_file>" >&2
                exit 1
            fi
            
            local file="$1"
            local output="$2"
            
            echo "Scanning file: $file" >&2
            scan_file "$file"
            generate_sarif_output "$output" "$(dirname "$file")"
            
            echo "SARIF report generated: $output" >&2
            echo "Found ${#FINDINGS[@]} issue(s)" >&2
            ;;
        *)
            echo "Usage: $0 {scan|file} <args>" >&2
            echo "" >&2
            echo "  scan <directory> <output_file> [pattern]" >&2
            echo "    Scan all files matching pattern in directory" >&2
            echo "" >&2
            echo "  file <file> <output_file>" >&2
            echo "    Scan a single file" >&2
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
