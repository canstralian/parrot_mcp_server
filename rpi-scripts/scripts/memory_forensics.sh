#!/usr/bin/env bash
# memory_forensics.sh - Memory forensics using Volatility 3
# Author: Canstralian
# Description: Analyze memory dumps using Volatility 3 framework
# Usage: ./memory_forensics.sh [OPTIONS]

set -euo pipefail

# Load forensics common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./forensics_common.sh
source "${SCRIPT_DIR}/scripts/forensics_common.sh"

# ============================================================================
# MEMORY FORENSICS CONFIGURATION
# ============================================================================

MEMORY_DUMP=""
PLUGINS="pslist"
OUTPUT_FORMAT="json"
ANALYSIS_ID=""

# ============================================================================
# VOLATILITY INTEGRATION
# ============================================================================

# Check if Volatility 3 is available
check_volatility() {
    parrot_info "Checking Volatility 3 installation..."
    
    if ! forensics_check_command "vol" "pip3 install volatility3"; then
        if ! forensics_check_python_package "volatility3" "pip3 install volatility3"; then
            parrot_error "Volatility 3 not found. Please install it first."
            parrot_warn "Install with: pip3 install volatility3"
            return 1
        fi
        # Try using python module directly
        alias vol='python3 -m volatility3.cli'
    fi
    
    parrot_info "Volatility 3 is available"
    return 0
}

# Run Volatility plugin
run_volatility_plugin() {
    local dump_file="$1"
    local plugin="$2"
    local output_file="$3"
    
    parrot_info "Running Volatility plugin: $plugin"
    forensics_report_progress "Memory Analysis" "" "Running $plugin on $(basename "$dump_file")"
    
    # Check if we have a cached result
    local cache_key
    cache_key="mem_$(forensics_compute_hash "$dump_file" md5)_${plugin}"
    
    if forensics_check_cache "$cache_key" > "$output_file" 2>/dev/null; then
        parrot_info "Using cached result for $plugin"
        return 0
    fi
    
    # Run Volatility
    local vol_cmd="vol"
    if ! command -v vol &>/dev/null; then
        vol_cmd="python3 -m volatility3.cli"
    fi
    
    # Build command based on plugin
    if $vol_cmd -f "$dump_file" "$plugin" --output json > "$output_file" 2>&1; then
        parrot_info "Successfully ran plugin: $plugin"
        # Cache the result
        forensics_save_cache "$cache_key" "$(cat "$output_file")"
        return 0
    else
        parrot_warn "Plugin $plugin failed or produced no output"
        # Try without JSON output format
        if $vol_cmd -f "$dump_file" "$plugin" > "$output_file" 2>&1; then
            parrot_info "Successfully ran plugin: $plugin (text format)"
            forensics_save_cache "$cache_key" "$(cat "$output_file")"
            return 0
        fi
        return 1
    fi
}

# ============================================================================
# IOC EXTRACTION
# ============================================================================

# Extract IOCs from memory analysis results
extract_iocs() {
    local result_dir="$1"
    local ioc_file="${result_dir}/iocs.json"
    
    parrot_info "Extracting IOCs from analysis results..."
    
    # Initialize IOC structure
    cat > "$ioc_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "analysis_id": "$(basename "$result_dir")",
  "iocs": {
    "ip_addresses": [],
    "domains": [],
    "file_paths": [],
    "registry_keys": [],
    "suspicious_processes": []
  }
}
EOF
    
    # Extract IPs from netscan results if available
    if [ -f "${result_dir}/netscan.txt" ]; then
        parrot_info "Extracting IP addresses from network connections..."
        # Extract IPs using grep and awk
        grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "${result_dir}/netscan.txt" 2>/dev/null | \
            sort -u > "${result_dir}/ips.txt" || true
    fi
    
    # Extract suspicious processes from malfind results
    if [ -f "${result_dir}/malfind.txt" ]; then
        parrot_info "Extracting suspicious process information..."
        grep -i "process" "${result_dir}/malfind.txt" 2>/dev/null | \
            sort -u > "${result_dir}/suspicious_procs.txt" || true
    fi
    
    parrot_info "IOC extraction complete: $ioc_file"
    echo "$ioc_file"
}

# ============================================================================
# TIMELINE GENERATION
# ============================================================================

# Generate timeline from memory artifacts
generate_timeline() {
    local result_dir="$1"
    local timeline_file="${result_dir}/timeline.csv"
    
    parrot_info "Generating timeline from memory artifacts..."
    
    # Create CSV header
    echo "timestamp,event_type,description,source" > "$timeline_file"
    
    # Process pslist for process creation times if available
    if [ -f "${result_dir}/pslist.txt" ]; then
        parrot_info "Adding process events to timeline..."
        # This is a simplified extraction - real implementation would parse Volatility output
        grep -i "create" "${result_dir}/pslist.txt" 2>/dev/null >> "$timeline_file" || true
    fi
    
    parrot_info "Timeline generation complete: $timeline_file"
    echo "$timeline_file"
}

# ============================================================================
# MAIN ANALYSIS FUNCTION
# ============================================================================

analyze_memory() {
    local dump_file="$1"
    local plugins_list="$2"
    local output_format="${3:-json}"
    
    # Validate dump file
    if [ ! -f "$dump_file" ]; then
        forensics_handle_error "analyze_memory" "Memory dump file not found: $dump_file"
        return 1
    fi
    
    # Generate analysis ID
    ANALYSIS_ID=$(forensics_generate_id "memory")
    local result_dir
    result_dir=$(forensics_create_result_dir "$ANALYSIS_ID")
    
    parrot_info "Starting memory analysis: $ANALYSIS_ID"
    parrot_info "Memory dump: $dump_file"
    parrot_info "Output directory: $result_dir"
    
    # Save analysis metadata
    cat > "${result_dir}/metadata.json" <<EOF
{
  "analysis_id": "$ANALYSIS_ID",
  "timestamp": "$(date -Iseconds)",
  "dump_file": "$dump_file",
  "dump_size": $(stat -c %s "$dump_file"),
  "dump_hash": "$(forensics_compute_hash "$dump_file")",
  "plugins": "$plugins_list",
  "output_format": "$output_format"
}
EOF
    
    # Run each plugin
    IFS=',' read -ra PLUGIN_ARRAY <<< "$plugins_list"
    local total_plugins=${#PLUGIN_ARRAY[@]}
    local current=0
    
    for plugin in "${PLUGIN_ARRAY[@]}"; do
        current=$((current + 1))
        local percent=$((current * 100 / total_plugins))
        forensics_report_progress "Memory Analysis" "$percent" "Processing plugin $current/$total_plugins: $plugin"
        
        local output_file="${result_dir}/${plugin}.txt"
        if run_volatility_plugin "$dump_file" "$plugin" "$output_file"; then
            parrot_info "Plugin $plugin completed successfully"
        else
            parrot_warn "Plugin $plugin failed, continuing with next plugin"
        fi
    done
    
    # Extract IOCs
    extract_iocs "$result_dir"
    
    # Generate timeline
    generate_timeline "$result_dir"
    
    # Create summary
    cat > "${result_dir}/summary.txt" <<EOF
Memory Forensics Analysis Summary
==================================
Analysis ID: $ANALYSIS_ID
Timestamp: $(date)
Memory Dump: $dump_file
Dump Size: $(stat -c %s "$dump_file" | numfmt --to=iec-i --suffix=B)
Dump Hash (SHA256): $(forensics_compute_hash "$dump_file")

Plugins Executed: $plugins_list
Results Directory: $result_dir

Artifacts Generated:
$(find "$result_dir" -maxdepth 1 -type f -printf "  - %f\\n" | sort)

Analysis Complete.
EOF
    
    parrot_info "Memory analysis complete!"
    parrot_info "Results saved to: $result_dir"
    cat "${result_dir}/summary.txt"
    
    echo "$ANALYSIS_ID"
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

show_help() {
    cat <<EOF
Memory Forensics Tool - Volatility 3 Wrapper

Usage: $0 [OPTIONS]

Options:
  -d, --dump FILE       Path to memory dump file (required)
  -p, --plugins LIST    Comma-separated list of plugins (default: pslist)
  -f, --format FORMAT   Output format: json, csv, text (default: json)
  -o, --output DIR      Output directory (auto-generated if not specified)
  -l, --list-plugins    List available Volatility plugins
  -c, --check           Check dependencies only
  -h, --help            Show this help message

Available Plugins (common):
  pslist      - List processes
  pstree      - Process tree
  netscan     - Network connections
  malfind     - Find malicious code
  dlllist     - List DLLs
  handles     - List handles
  cmdline     - Command line arguments
  filescan    - Scan for file objects

Examples:
  # Analyze memory dump with default plugins
  $0 -d /path/to/memory.dump

  # Run specific plugins
  $0 -d /path/to/memory.dump -p "pslist,netscan,malfind"

  # Check dependencies
  $0 --check

EOF
}

list_plugins() {
    cat <<EOF
Common Volatility 3 Plugins:

Process Analysis:
  pslist      - List running processes
  pstree      - Display process tree
  psscan      - Scan for EPROCESS structures
  psxview     - Cross-reference process listings
  cmdline     - Display command-line arguments

Network Analysis:
  netscan     - Scan for network connections
  netstat     - Network statistics

Malware Detection:
  malfind     - Find malicious code patterns
  apihooks    - Detect API hooks
  ldrmodules  - Detect unlinked DLLs

File Analysis:
  filescan    - Scan for file objects
  dumpfiles   - Extract files from memory
  handles     - List open handles

Registry Analysis:
  hivelist    - List registry hives
  printkey    - Print registry key values

Memory Analysis:
  memmap      - Display memory map
  vadinfo     - Display VAD information
  dlllist     - List loaded DLLs

For a complete list, run: vol --help
EOF
}

# Parse command line arguments
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dump)
                MEMORY_DUMP="$2"
                shift 2
                ;;
            -p|--plugins)
                PLUGINS="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -l|--list-plugins)
                list_plugins
                exit 0
                ;;
            -c|--check)
                forensics_check_dependencies
                check_volatility
                exit $?
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                parrot_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$MEMORY_DUMP" ]; then
        parrot_error "Memory dump file is required"
        show_help
        exit 1
    fi
    
    # Check dependencies
    if ! check_volatility; then
        exit 1
    fi
    
    # Run analysis
    analyze_memory "$MEMORY_DUMP" "$PLUGINS" "$OUTPUT_FORMAT"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
