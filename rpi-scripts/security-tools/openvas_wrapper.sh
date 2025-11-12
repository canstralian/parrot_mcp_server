#!/usr/bin/env bash
# OpenVAS/GVM Wrapper Script
# Provides sandboxed, validated execution of OpenVAS vulnerability scans
#
# ⚠️  WARNING: FOR AUTHORIZED SECURITY TESTING ONLY
# This tool must ONLY be used against systems you own or have explicit
# written permission to test. Unauthorized use is ILLEGAL.

set -euo pipefail

# Load configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/security_config.sh"

# =============================================================================
# OPENVAS WRAPPER FUNCTIONS
# =============================================================================

# Display usage
openvas_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OpenVAS/GVM wrapper for authorized vulnerability scanning.

OPTIONS:
    -t, --target TARGET     Target IP or hostname (required)
    -c, --config CONFIG     Scan configuration (default: full_and_fast)
    -n, --name NAME         Scan name/description
    -o, --output FILE       Output file basename (auto-generated if not specified)
    -u, --user USER         Username for authentication
    -k, --api-key KEY       API key for authentication
    -w, --wait              Wait for scan completion (default: false)
    -h, --help              Show this help message

SCAN CONFIGURATIONS:
    full_and_fast          Full and fast scan (default)
    full_and_deep          Full and deep scan
    discovery              Network discovery only
    system_discovery       System discovery

EXAMPLES:
    # Quick vulnerability scan
    $0 -t 192.168.1.100 -c full_and_fast -u admin -k your_api_key

    # Deep scan with custom name
    $0 -t 192.168.1.0/24 -c full_and_deep -n "Production Network" -u admin -k your_api_key

    # Wait for completion
    $0 -t 192.168.1.100 --wait -u admin -k your_api_key

EOF
}

# Check if OpenVAS/GVM is installed and running
openvas_check_installed() {
    # Check if gvm-cli is available
    if [ ! -x "$OPENVAS_BIN" ]; then
        security_audit "ERROR" "OpenVAS/GVM CLI not found at: $OPENVAS_BIN"
        echo "ERROR: OpenVAS/GVM is not installed or not found" >&2
        echo "Install with: sudo apt-get install gvm" >&2
        return 1
    fi

    # Check if GVM socket exists
    if [ ! -S "$OPENVAS_SOCKET" ]; then
        security_audit "ERROR" "GVM socket not found at: $OPENVAS_SOCKET"
        echo "ERROR: GVM daemon is not running" >&2
        echo "Start with: sudo gvm-start" >&2
        return 1
    fi

    security_audit "INFO" "OpenVAS/GVM is available"
    return 0
}

# Authenticate with OpenVAS
openvas_authenticate() {
    # Read password from file
    if [ ! -f "$OPENVAS_PASSWORD_FILE" ]; then
        security_audit "ERROR" "OpenVAS password file not found: $OPENVAS_PASSWORD_FILE"
        echo "ERROR: OpenVAS password not configured" >&2
        echo "Create file: echo 'your_password' > $OPENVAS_PASSWORD_FILE && chmod 600 $OPENVAS_PASSWORD_FILE" >&2
        return 1
    fi

    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    # Test authentication by listing scan configs
    if ! "$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "<get_configs/>" \
        --username "$OPENVAS_USERNAME" \
        --password "$password" >/dev/null 2>&1; then
        security_audit "ERROR" "OpenVAS authentication failed"
        echo "ERROR: Failed to authenticate with OpenVAS" >&2
        return 1
    fi

    security_audit "INFO" "OpenVAS authentication successful"
    return 0
}

# Get scan configuration UUID
openvas_get_config_uuid() {
    local config_name="$1"
    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    # Map friendly names to UUIDs (these are standard GVM UUIDs)
    case "$config_name" in
        full_and_fast)
            echo "daba56c8-73ec-11df-a475-002264764cea"
            ;;
        full_and_deep)
            echo "698f691e-7489-11df-9d8c-002264764cea"
            ;;
        discovery)
            echo "8715c877-47a0-438d-98a3-27c7a6ab2196"
            ;;
        system_discovery)
            echo "bbca7412-a950-11e3-9109-406186ea4fc5"
            ;;
        *)
            # Try to look up by name
            local uuid
            uuid=$("$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
                --xml "<get_configs/>" \
                --username "$OPENVAS_USERNAME" \
                --password "$password" | \
                grep -A 1 "<name>$config_name</name>" | \
                grep 'id="' | \
                sed 's/.*id="\([^"]*\)".*/\1/')

            if [ -z "$uuid" ]; then
                security_audit "ERROR" "Unknown scan configuration: $config_name"
                echo "ERROR: Unknown scan configuration: $config_name" >&2
                return 1
            fi

            echo "$uuid"
            ;;
    esac
}

# Create target in OpenVAS
openvas_create_target() {
    local target_ip="$1"
    local target_name="$2"
    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    local xml_request
    xml_request="<create_target>
        <name>$target_name</name>
        <hosts>$target_ip</hosts>
    </create_target>"

    local response
    response=$("$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password")

    # Extract target UUID
    local target_uuid
    target_uuid=$(echo "$response" | grep 'id="' | sed 's/.*id="\([^"]*\)".*/\1/' | head -n1)

    if [ -z "$target_uuid" ]; then
        security_audit "ERROR" "Failed to create OpenVAS target"
        echo "ERROR: Failed to create target in OpenVAS" >&2
        return 1
    fi

    echo "$target_uuid"
}

# Create task in OpenVAS
openvas_create_task() {
    local task_name="$1"
    local target_uuid="$2"
    local config_uuid="$3"
    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    local xml_request
    xml_request="<create_task>
        <name>$task_name</name>
        <target id=\"$target_uuid\"/>
        <config id=\"$config_uuid\"/>
    </create_task>"

    local response
    response=$("$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password")

    # Extract task UUID
    local task_uuid
    task_uuid=$(echo "$response" | grep 'id="' | sed 's/.*id="\([^"]*\)".*/\1/' | head -n1)

    if [ -z "$task_uuid" ]; then
        security_audit "ERROR" "Failed to create OpenVAS task"
        echo "ERROR: Failed to create task in OpenVAS" >&2
        return 1
    fi

    echo "$task_uuid"
}

# Start scan task
openvas_start_task() {
    local task_uuid="$1"
    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    local xml_request
    xml_request="<start_task task_id=\"$task_uuid\"/>"

    local response
    response=$("$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password")

    # Check for errors
    if echo "$response" | grep -q "status=\"4\""; then
        security_audit "ERROR" "Failed to start OpenVAS task"
        echo "ERROR: Failed to start scan task" >&2
        return 1
    fi

    security_audit "INFO" "OpenVAS task started: $task_uuid"
    return 0
}

# Get task status
openvas_get_task_status() {
    local task_uuid="$1"
    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    local xml_request
    xml_request="<get_tasks task_id=\"$task_uuid\"/>"

    local response
    response=$("$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password")

    # Extract status
    local status
    status=$(echo "$response" | grep "<status>" | sed 's/.*<status>\(.*\)<\/status>.*/\1/')

    echo "$status"
}

# Wait for task completion
openvas_wait_for_completion() {
    local task_uuid="$1"
    local max_wait="$OPENVAS_TIMEOUT"
    local elapsed=0
    local interval=30

    echo "Waiting for scan to complete (max ${max_wait}s)..." >&2

    while [ "$elapsed" -lt "$max_wait" ]; do
        local status
        status=$(openvas_get_task_status "$task_uuid")

        case "$status" in
            Done)
                echo "Scan completed successfully" >&2
                return 0
                ;;
            Stopped|Interrupted)
                echo "Scan was stopped or interrupted" >&2
                return 1
                ;;
            Running|Requested)
                echo "Scan in progress... (${elapsed}s/${max_wait}s)" >&2
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
            *)
                echo "Unknown scan status: $status" >&2
                return 1
                ;;
        esac
    done

    echo "Scan timeout reached (${max_wait}s)" >&2
    return 1
}

# Get scan results
openvas_get_results() {
    local task_uuid="$1"
    local output_file="$2"
    local password
    password=$(cat "$OPENVAS_PASSWORD_FILE")

    # Get report UUID for this task
    local xml_request
    xml_request="<get_tasks task_id=\"$task_uuid\" details=\"1\"/>"

    local response
    response=$("$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password")

    local report_uuid
    report_uuid=$(echo "$response" | grep "report id=" | sed 's/.*report id="\([^"]*\)".*/\1/' | head -n1)

    if [ -z "$report_uuid" ]; then
        security_audit "ERROR" "Failed to get report UUID"
        return 1
    fi

    # Download report in XML format
    xml_request="<get_reports report_id=\"$report_uuid\" format_id=\"a994b278-1f62-11e1-96ac-406186ea4fc5\"/>"

    "$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password" > "${output_file}.xml"

    # Download report in HTML format (if available)
    xml_request="<get_reports report_id=\"$report_uuid\" format_id=\"6c248850-1f62-11e1-b082-406186ea4fc5\"/>"

    "$OPENVAS_BIN" socket --socketpath "$OPENVAS_SOCKET" \
        --xml "$xml_request" \
        --username "$OPENVAS_USERNAME" \
        --password "$password" > "${output_file}.html" 2>/dev/null || true

    security_audit "INFO" "OpenVAS results saved: $output_file"
    return 0
}

# Execute OpenVAS scan
openvas_execute() {
    local target="$1"
    local config_name="$2"
    local scan_name="$3"
    local output_basename="$4"
    local user="$5"
    local wait_for_completion="$6"

    # Generate scan ID
    local scan_id
    scan_id="openvas_$(date +%Y%m%d_%H%M%S)_$$"

    # Use scan name or default
    if [ -z "$scan_name" ]; then
        scan_name="Scan of $target at $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    # Prepare output file
    local output_file="${SECURITY_RESULTS_DIR}/${output_basename:-$scan_id}"

    security_audit "INFO" "Starting OpenVAS scan: target=$target, config=$config_name, user=$user, scan_id=$scan_id"

    # Authenticate
    openvas_authenticate || return 1

    # Get config UUID
    local config_uuid
    config_uuid=$(openvas_get_config_uuid "$config_name") || return 1

    # Create target
    local target_uuid
    target_uuid=$(openvas_create_target "$target" "${scan_name}_target") || return 1

    # Create task
    local task_uuid
    task_uuid=$(openvas_create_task "$scan_name" "$target_uuid" "$config_uuid") || return 1

    # Start task
    openvas_start_task "$task_uuid" || return 1

    security_audit "INFO" "OpenVAS scan started: task_uuid=$task_uuid"

    # Wait for completion if requested
    if [ "$wait_for_completion" = "true" ]; then
        if openvas_wait_for_completion "$task_uuid"; then
            openvas_get_results "$task_uuid" "$output_file"

            # Encrypt results
            if [ "$SECURITY_ENCRYPT_RESULTS" = "true" ]; then
                for ext in xml html; do
                    if [ -f "${output_file}.${ext}" ]; then
                        security_encrypt_file "${output_file}.${ext}" >/dev/null
                    fi
                done
            fi
        fi
    fi

    # Return result information
    cat <<EOF
{
    "scan_id": "$scan_id",
    "task_uuid": "$task_uuid",
    "target": "$target",
    "config": "$config_name",
    "scan_name": "$scan_name",
    "status": "$([ "$wait_for_completion" = "true" ] && echo 'completed' || echo 'running')",
    "output_files": {
        "xml": "${output_file}.xml$([ "$SECURITY_ENCRYPT_RESULTS" = "true" ] && echo '.enc' || echo '')",
        "html": "${output_file}.html$([ "$SECURITY_ENCRYPT_RESULTS" = "true" ] && echo '.enc' || echo '')"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

    return 0
}

# Main function
main() {
    local target=""
    local config="full_and_fast"
    local scan_name=""
    local output=""
    local user=""
    local api_key=""
    local wait_for_completion="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--target)
                target="$2"
                shift 2
                ;;
            -c|--config)
                config="$2"
                shift 2
                ;;
            -n|--name)
                scan_name="$2"
                shift 2
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            -u|--user)
                user="$2"
                shift 2
                ;;
            -k|--api-key)
                api_key="$2"
                shift 2
                ;;
            -w|--wait)
                wait_for_completion="true"
                shift
                ;;
            -h|--help)
                openvas_usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                openvas_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$target" ]; then
        echo "ERROR: Target is required (-t/--target)" >&2
        openvas_usage
        exit 1
    fi

    if [ -z "$user" ]; then
        user="${SUDO_USER:-${USER}}"
    fi

    # Check if OpenVAS is installed and running
    openvas_check_installed || exit 1

    # Authenticate user
    if [ "$SECURITY_REQUIRE_AUTH" = "true" ]; then
        if [ -z "$api_key" ]; then
            echo "ERROR: API key required for authentication (-k/--api-key)" >&2
            exit 1
        fi

        security_validate_api_key "$api_key" "$user" || {
            echo "ERROR: Authentication failed" >&2
            exit 1
        }
    fi

    # Check user authorization
    security_check_user "$user" || {
        echo "ERROR: User not authorized: $user" >&2
        exit 1
    }

    # Check rate limit
    security_check_rate_limit "$user" "openvas_scan" || {
        echo "ERROR: Rate limit exceeded. Maximum $SECURITY_MAX_SCANS_PER_HOUR scans per hour." >&2
        exit 1
    }

    # Validate target against whitelist/blacklist
    security_validate_target "$target" || {
        echo "ERROR: Target not authorized: $target" >&2
        echo "Check IP whitelist at: $SECURITY_IP_WHITELIST_FILE" >&2
        exit 1
    }

    # Execute scan
    openvas_execute "$target" "$config" "$scan_name" "$output" "$user" "$wait_for_completion"
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
