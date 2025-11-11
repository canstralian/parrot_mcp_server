#!/usr/bin/env bash
# Nmap Wrapper Script
# Provides sandboxed, validated execution of Nmap scans
#
# ⚠️  WARNING: FOR AUTHORIZED SECURITY TESTING ONLY
# This tool must ONLY be used against systems you own or have explicit
# written permission to test. Unauthorized use is ILLEGAL.

set -euo pipefail

# Load configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/security_config.sh"

# =============================================================================
# NMAP WRAPPER FUNCTIONS
# =============================================================================

# Display usage
nmap_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Nmap wrapper for authorized security testing.

OPTIONS:
    -t, --target TARGET     Target IP or hostname (required)
    -s, --scan-type TYPE    Scan type: tcp, udp, version, ping (default: tcp)
    -p, --ports PORTS       Port specification (default: top 1000)
    -o, --output FILE       Output file basename (auto-generated if not specified)
    -u, --user USER         Username for authentication
    -k, --api-key KEY       API key for authentication
    -h, --help              Show this help message

EXAMPLES:
    # Basic TCP SYN scan
    $0 -t 192.168.1.100 -s tcp -u admin -k your_api_key

    # Version detection scan
    $0 -t 192.168.1.0/24 -s version -p 22,80,443 -u admin -k your_api_key

    # Ping sweep (no port scan)
    $0 -t 192.168.1.0/24 -s ping -u admin -k your_api_key

EOF
}

# Validate Nmap is installed
nmap_check_installed() {
    if [ ! -x "$NMAP_BIN" ]; then
        security_audit "ERROR" "Nmap not found at: $NMAP_BIN"
        echo "ERROR: Nmap is not installed or not found at $NMAP_BIN" >&2
        echo "Install with: sudo apt-get install nmap" >&2
        return 1
    fi

    # Check version
    local version
    version=$("$NMAP_BIN" --version | head -n1)
    security_audit "INFO" "Using Nmap: $version"

    return 0
}

# Validate scan type
nmap_validate_scan_type() {
    local scan_type="$1"

    case "$scan_type" in
        tcp|sS)
            echo "-sS"  # TCP SYN scan
            ;;
        tcp-connect|sT)
            echo "-sT"  # TCP connect scan
            ;;
        udp|sU)
            echo "-sU"  # UDP scan
            ;;
        version|sV)
            echo "-sV"  # Version detection
            ;;
        ping|sn)
            echo "-sn"  # Ping scan (no port scan)
            ;;
        os|O)
            echo "-O"   # OS detection
            ;;
        default|sC)
            echo "-sC"  # Default scripts
            ;;
        *)
            security_audit "ERROR" "Invalid scan type: $scan_type"
            echo "ERROR: Invalid scan type. Allowed: tcp, udp, version, ping, os, default" >&2
            return 1
            ;;
    esac
}

# Validate ports specification
nmap_validate_ports() {
    local ports="$1"

    # If empty, use default
    if [ -z "$ports" ]; then
        echo "--top-ports 1000"
        return 0
    fi

    # Check for valid port specification
    # Allowed: single port (80), range (1-1000), list (22,80,443), or --top-ports N
    if [[ "$ports" =~ ^[0-9,\-]+$ ]]; then
        # Count number of ports
        local port_count
        port_count=$(echo "$ports" | tr ',' '\n' | wc -l)

        if [ "$port_count" -gt "$NMAP_MAX_PORTS" ]; then
            security_audit "ERROR" "Too many ports specified: $port_count > $NMAP_MAX_PORTS"
            echo "ERROR: Too many ports. Maximum: $NMAP_MAX_PORTS" >&2
            return 1
        fi

        echo "-p $ports"
    elif [[ "$ports" =~ ^top-([0-9]+)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        if [ "$num" -gt "$NMAP_MAX_PORTS" ]; then
            security_audit "ERROR" "Top ports count too high: $num > $NMAP_MAX_PORTS"
            echo "ERROR: Top ports count exceeds maximum: $NMAP_MAX_PORTS" >&2
            return 1
        fi
        echo "--top-ports $num"
    else
        security_audit "ERROR" "Invalid port specification: $ports"
        echo "ERROR: Invalid port specification. Use: 80, 1-1000, 22,80,443, or top-N" >&2
        return 1
    fi
}

# Build Nmap command with safety checks
nmap_build_command() {
    local target="$1"
    local scan_type="$2"
    local ports="$3"
    local output_file="$4"

    local cmd=("$NMAP_BIN")

    # Add scan type
    local scan_flag
    scan_flag=$(nmap_validate_scan_type "$scan_type") || return 1
    cmd+=("$scan_flag")

    # Add port specification
    if [ "$scan_type" != "ping" ] && [ "$scan_type" != "sn" ]; then
        local port_flag
        port_flag=$(nmap_validate_ports "$ports") || return 1
        # shellcheck disable=SC2206
        cmd+=($port_flag)  # Don't quote to allow multiple args
    fi

    # Add safety options
    cmd+=(
        "--max-retries" "2"              # Limit retries
        "--host-timeout" "${NMAP_TIMEOUT}s"  # Overall timeout
        "--max-rtt-timeout" "500ms"      # RTT timeout
        "--initial-rtt-timeout" "100ms"  # Initial RTT
        "-T3"                            # Normal timing (not aggressive)
        "--min-rate" "10"                # Minimum rate (gentle)
        "--max-rate" "100"               # Maximum rate (prevent flooding)
    )

    # Add output options
    cmd+=(
        "-oN" "${output_file}.txt"       # Normal output
        "-oX" "${output_file}.xml"       # XML output
    )

    # Add verbosity
    cmd+=("-v")

    # Add target (must be last)
    cmd+=("$target")

    # Return command as string
    echo "${cmd[@]}"
}

# Execute Nmap scan
nmap_execute() {
    local target="$1"
    local scan_type="$2"
    local ports="$3"
    local output_basename="$4"
    local user="$5"

    # Generate scan ID
    local scan_id
    scan_id="nmap_$(date +%Y%m%d_%H%M%S)_$$"

    # Prepare output file
    local output_file="${SECURITY_RESULTS_DIR}/${output_basename:-$scan_id}"

    security_audit "INFO" "Starting Nmap scan: target=$target, type=$scan_type, user=$user, scan_id=$scan_id"

    # Build command
    local cmd
    cmd=$(nmap_build_command "$target" "$scan_type" "$ports" "$output_file") || return 1

    security_audit "INFO" "Nmap command: $cmd"

    # Execute with timeout
    local exit_code=0
    if timeout "$NMAP_TIMEOUT" bash -c "$cmd" >"${output_file}.log" 2>&1; then
        exit_code=0
        security_audit "INFO" "Nmap scan completed successfully: scan_id=$scan_id"
    else
        exit_code=$?
        security_audit "ERROR" "Nmap scan failed: scan_id=$scan_id, exit_code=$exit_code"
    fi

    # Encrypt results if configured
    if [ "$SECURITY_ENCRYPT_RESULTS" = "true" ]; then
        for ext in txt xml log; do
            if [ -f "${output_file}.${ext}" ]; then
                security_encrypt_file "${output_file}.${ext}" >/dev/null
            fi
        done
    fi

    # Return result information
    cat <<EOF
{
    "scan_id": "$scan_id",
    "target": "$target",
    "scan_type": "$scan_type",
    "status": "$([ $exit_code -eq 0 ] && echo 'completed' || echo 'failed')",
    "exit_code": $exit_code,
    "output_files": {
        "txt": "${output_file}.txt$([ "$SECURITY_ENCRYPT_RESULTS" = "true" ] && echo '.enc' || echo '')",
        "xml": "${output_file}.xml$([ "$SECURITY_ENCRYPT_RESULTS" = "true" ] && echo '.enc' || echo '')",
        "log": "${output_file}.log$([ "$SECURITY_ENCRYPT_RESULTS" = "true" ] && echo '.enc' || echo '')"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

    return $exit_code
}

# Main function
main() {
    local target=""
    local scan_type="tcp"
    local ports=""
    local output=""
    local user=""
    local api_key=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--target)
                target="$2"
                shift 2
                ;;
            -s|--scan-type)
                scan_type="$2"
                shift 2
                ;;
            -p|--ports)
                ports="$2"
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
            -h|--help)
                nmap_usage
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                nmap_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$target" ]; then
        echo "ERROR: Target is required (-t/--target)" >&2
        nmap_usage
        exit 1
    fi

    if [ -z "$user" ]; then
        user="${SUDO_USER:-${USER}}"
    fi

    # Check if Nmap is installed
    nmap_check_installed || exit 1

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
    security_check_rate_limit "$user" "nmap_scan" || {
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
    nmap_execute "$target" "$scan_type" "$ports" "$output" "$user"
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
