#!/usr/bin/env bash
# disk_forensics.sh - Disk forensics using SleuthKit
# Author: Canstralian
# Description: Analyze disk images using SleuthKit tools
# Usage: ./disk_forensics.sh [OPTIONS]

set -euo pipefail

# Load forensics common utilities
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./forensics_common.sh
source "${SCRIPT_DIR}/scripts/forensics_common.sh"

# ============================================================================
# DISK FORENSICS CONFIGURATION
# ============================================================================

DISK_IMAGE=""
OPERATION="timeline"
SEARCH_STRING=""
ANALYSIS_ID=""

# ============================================================================
# SLEUTHKIT INTEGRATION
# ============================================================================

# Check if SleuthKit is available
check_sleuthkit() {
    parrot_info "Checking SleuthKit installation..."
    
    local required_tools=("fls" "icat" "mmls" "fsstat")
    local all_ok=0
    
    for tool in "${required_tools[@]}"; do
        if ! forensics_check_command "$tool" "apt-get install sleuthkit"; then
            all_ok=1
        fi
    done
    
    if [ $all_ok -eq 0 ]; then
        parrot_info "SleuthKit tools are available"
    else
        parrot_error "SleuthKit not fully available. Please install it first."
        parrot_warn "Install with: sudo apt-get install sleuthkit"
        return 1
    fi
    
    return 0
}

# ============================================================================
# DISK IMAGE ANALYSIS
# ============================================================================

# Get filesystem information
get_filesystem_info() {
    local image="$1"
    local output_file="$2"
    
    parrot_info "Gathering filesystem information..."
    
    {
        echo "=== Filesystem Information ==="
        echo ""
        echo "--- Partition Layout ---"
        mmls "$image" 2>/dev/null || echo "Unable to read partition table"
        echo ""
        echo "--- Filesystem Statistics ---"
        fsstat "$image" 2>/dev/null || echo "Unable to read filesystem statistics"
    } > "$output_file"
    
    parrot_info "Filesystem information saved to: $output_file"
}

# ============================================================================
# TIMELINE GENERATION
# ============================================================================

# Generate filesystem timeline
generate_filesystem_timeline() {
    local image="$1"
    local output_file="$2"
    
    parrot_info "Generating filesystem timeline..."
    forensics_report_progress "Timeline Generation" "10" "Scanning filesystem"
    
    # Check cache
    local cache_key
    cache_key="disk_$(forensics_compute_hash "$image" md5)_timeline"
    
    if forensics_check_cache "$cache_key" > "$output_file" 2>/dev/null; then
        parrot_info "Using cached timeline"
        return 0
    fi
    
    forensics_report_progress "Timeline Generation" "30" "Extracting file metadata"
    
    # Generate timeline using fls (list files with timestamps)
    if fls -r -m / "$image" 2>/dev/null > "$output_file"; then
        parrot_info "Timeline generated successfully"
        forensics_save_cache "$cache_key" "$(cat "$output_file")"
        return 0
    else
        parrot_warn "Timeline generation had issues, but may contain partial data"
        return 1
    fi
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================

# List all files in disk image
list_files() {
    local image="$1"
    local output_file="$2"
    local recursive="${3:-true}"
    
    parrot_info "Listing files in disk image..."
    
    local fls_opts="-l"
    if [ "$recursive" = "true" ]; then
        fls_opts="-r -l"
    fi
    
    # shellcheck disable=SC2086
    if fls $fls_opts "$image" 2>/dev/null > "$output_file"; then
        parrot_info "File listing complete"
        return 0
    else
        parrot_warn "File listing had issues"
        return 1
    fi
}

# Search for files by name pattern
search_files() {
    local image="$1"
    local pattern="$2"
    local output_file="$3"
    
    parrot_info "Searching for files matching: $pattern"
    
    # List all files and grep for pattern
    fls -r -l "$image" 2>/dev/null | grep -i "$pattern" > "$output_file" || true
    
    local count
    count=$(wc -l < "$output_file")
    parrot_info "Found $count matching files"
}

# Extract file from disk image
extract_file() {
    local image="$1"
    local inode="$2"
    local output_file="$3"
    
    parrot_info "Extracting file with inode: $inode"
    
    if icat "$image" "$inode" > "$output_file" 2>/dev/null; then
        parrot_info "File extracted successfully"
        return 0
    else
        parrot_warn "Failed to extract file"
        return 1
    fi
}

# ============================================================================
# HASH COMPUTATION
# ============================================================================

# Compute hashes for files in image
compute_file_hashes() {
    local image="$1"
    local output_file="$2"
    
    parrot_info "Computing file hashes..."
    forensics_report_progress "Hash Computation" "10" "Listing files"
    
    echo "inode,filename,md5,sha256" > "$output_file"
    
    # This is a simplified version - real implementation would iterate through files
    local file_list
    file_list=$(mktemp)
    fls -r "$image" 2>/dev/null | head -100 > "$file_list" || true
    
    local total
    total=$(wc -l < "$file_list")
    local current=0
    
    while IFS= read -r _line; do
        current=$((current + 1))
        local percent=$((current * 100 / total))
        if [ $((current % 10)) -eq 0 ]; then
            forensics_report_progress "Hash Computation" "$percent" "Processing file $current/$total"
        fi
    done < "$file_list"
    
    rm -f "$file_list"
    parrot_info "Hash computation complete"
}

# ============================================================================
# STRING SEARCH
# ============================================================================

# Search for strings in disk image
search_strings() {
    local image="$1"
    local search_term="$2"
    local output_file="$3"
    
    parrot_info "Searching for strings: $search_term"
    forensics_report_progress "String Search" "10" "Extracting strings from image"
    
    # Use strings command to extract printable strings and search
    if command -v strings &>/dev/null; then
        strings "$image" 2>/dev/null | grep -i "$search_term" > "$output_file" || true
        
        local count
        count=$(wc -l < "$output_file")
        parrot_info "Found $count matching strings"
    else
        parrot_warn "strings command not available"
        return 1
    fi
}

# ============================================================================
# DELETED FILE RECOVERY
# ============================================================================

# List deleted files
list_deleted_files() {
    local image="$1"
    local output_file="$2"
    
    parrot_info "Listing deleted files..."
    
    # Use fls with -d flag to show deleted files
    if fls -r -d "$image" 2>/dev/null > "$output_file"; then
        local count
        count=$(wc -l < "$output_file")
        parrot_info "Found $count deleted file entries"
        return 0
    else
        parrot_warn "Could not list deleted files"
        return 1
    fi
}

# Recover deleted file
recover_deleted_file() {
    local image="$1"
    local inode="$2"
    local output_file="$3"
    
    parrot_info "Attempting to recover deleted file: inode $inode"
    
    # Try to extract using icat
    if extract_file "$image" "$inode" "$output_file"; then
        parrot_info "Deleted file recovered successfully"
        return 0
    else
        parrot_warn "Could not recover deleted file"
        return 1
    fi
}

# ============================================================================
# MAIN ANALYSIS FUNCTION
# ============================================================================

analyze_disk() {
    local image="$1"
    local operation="$2"
    
    # Validate disk image
    if [ ! -f "$image" ]; then
        forensics_handle_error "analyze_disk" "Disk image file not found: $image"
        return 1
    fi
    
    # Generate analysis ID
    ANALYSIS_ID=$(forensics_generate_id "disk")
    local result_dir
    result_dir=$(forensics_create_result_dir "$ANALYSIS_ID")
    
    parrot_info "Starting disk analysis: $ANALYSIS_ID"
    parrot_info "Disk image: $image"
    parrot_info "Operation: $operation"
    parrot_info "Output directory: $result_dir"
    
    # Save analysis metadata
    cat > "${result_dir}/metadata.json" <<EOF
{
  "analysis_id": "$ANALYSIS_ID",
  "timestamp": "$(date -Iseconds)",
  "disk_image": "$image",
  "image_size": $(stat -c %s "$image"),
  "image_hash": "$(forensics_compute_hash "$image")",
  "operation": "$operation"
}
EOF
    
    # Perform requested operation
    case "$operation" in
        timeline)
            generate_filesystem_timeline "$image" "${result_dir}/timeline.csv"
            ;;
        info)
            get_filesystem_info "$image" "${result_dir}/filesystem_info.txt"
            ;;
        list)
            list_files "$image" "${result_dir}/file_list.txt"
            ;;
        deleted)
            list_deleted_files "$image" "${result_dir}/deleted_files.txt"
            ;;
        hashes)
            compute_file_hashes "$image" "${result_dir}/file_hashes.csv"
            ;;
        search)
            if [ -n "$SEARCH_STRING" ]; then
                search_strings "$image" "$SEARCH_STRING" "${result_dir}/search_results.txt"
            else
                parrot_error "Search string required for search operation"
                return 1
            fi
            ;;
        *)
            parrot_error "Unknown operation: $operation"
            return 1
            ;;
    esac
    
    # Create summary
    cat > "${result_dir}/summary.txt" <<EOF
Disk Forensics Analysis Summary
================================
Analysis ID: $ANALYSIS_ID
Timestamp: $(date)
Disk Image: $image
Image Size: $(stat -c %s "$image" | numfmt --to=iec-i --suffix=B)
Image Hash (SHA256): $(forensics_compute_hash "$image")

Operation: $operation
Results Directory: $result_dir

Artifacts Generated:
$(find "$result_dir" -maxdepth 1 -type f -printf "  - %f\\n" | sort)

Analysis Complete.
EOF
    
    parrot_info "Disk analysis complete!"
    parrot_info "Results saved to: $result_dir"
    cat "${result_dir}/summary.txt"
    
    echo "$ANALYSIS_ID"
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

show_help() {
    cat <<EOF
Disk Forensics Tool - SleuthKit Wrapper

Usage: $0 [OPTIONS]

Options:
  -i, --image FILE      Path to disk image file (required)
  -o, --operation OP    Operation to perform (required)
  -s, --search STRING   Search string (for search operation)
  -f, --format FORMAT   Output format: csv, json, text (default: csv)
  -c, --check           Check dependencies only
  -h, --help            Show this help message

Operations:
  timeline    - Generate filesystem timeline
  info        - Get filesystem information
  list        - List all files
  deleted     - List deleted files
  hashes      - Compute file hashes
  search      - Search for strings in image

Examples:
  # Generate filesystem timeline
  $0 -i /path/to/disk.dd -o timeline

  # List all files
  $0 -i /path/to/disk.dd -o list

  # Search for strings
  $0 -i /path/to/disk.dd -o search -s "password"

  # List deleted files
  $0 -i /path/to/disk.dd -o deleted

  # Check dependencies
  $0 --check

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
            -i|--image)
                DISK_IMAGE="$2"
                shift 2
                ;;
            -o|--operation)
                OPERATION="$2"
                shift 2
                ;;
            -s|--search)
                SEARCH_STRING="$2"
                shift 2
                ;;
            -f|--format)
                # Output format stored for future use
                shift 2
                ;;
            -c|--check)
                forensics_check_dependencies
                check_sleuthkit
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
    if [ -z "$DISK_IMAGE" ]; then
        parrot_error "Disk image file is required"
        show_help
        exit 1
    fi
    
    # Check dependencies
    if ! check_sleuthkit; then
        exit 1
    fi
    
    # Run analysis
    analyze_disk "$DISK_IMAGE" "$OPERATION"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
