# IPC Security Guide

## Overview

The Parrot MCP Server currently uses **file-based Inter-Process Communication (IPC)** via `/tmp/mcp_in.json` and `/tmp/mcp_bad.json`. This approach has **critical security vulnerabilities** that must be addressed before production deployment.

This document explains:
- Why the current approach is insecure
- Secure alternatives with implementation examples
- Migration path from current implementation
- Security best practices for IPC

---

## Current Implementation

### File-Based IPC (`/tmp/mcp_in.json`)

**Location**: `rpi-scripts/start_mcp_server.sh`

```bash
# Current insecure implementation
while true; do
    if [ -f /tmp/mcp_in.json ]; then
        # Process message
        cat /tmp/mcp_in.json
        rm /tmp/mcp_in.json
    fi
    sleep 1
done
```

### Why This Is Insecure

#### 1. **World-Readable Files (Confidentiality Risk)**

Files in `/tmp` are typically created with default permissions, making them readable by any user:

```bash
$ ls -la /tmp/mcp_in.json
-rw-r--r-- 1 user user 256 Nov 11 10:30 /tmp/mcp_in.json
#    ↑ ↑  - World-readable, group-readable
```

**Attack Scenario**:
```bash
# Attacker reads sensitive data
$ watch -n 0.1 'cat /tmp/mcp_in.json 2>/dev/null'
```

#### 2. **Race Conditions (Integrity Risk)**

Multiple processes can access the file simultaneously:

```bash
# Process 1: Check if file exists
[ -f /tmp/mcp_in.json ]  # Returns true

# Process 2: Delete the file
rm /tmp/mcp_in.json

# Process 1: Try to read (file is gone!)
cat /tmp/mcp_in.json  # Error!
```

#### 3. **Symlink Attacks (Availability/Integrity Risk)**

Attacker can create symlinks to overwrite arbitrary files:

```bash
# Attacker creates malicious symlink
ln -s /etc/passwd /tmp/mcp_in.json

# Server writes to "mcp_in.json", actually overwrites /etc/passwd
echo '{"method":"ping"}' > /tmp/mcp_in.json  # OVERWRITES /etc/passwd!
```

#### 4. **Predictable Paths (All Risks)**

Attackers know exactly where to find the IPC files:

```bash
# Attacker can monitor, inject, or replace messages
$ inotifywait -m /tmp/mcp_in.json
```

#### 5. **No Authentication/Authorization**

Any process can send messages to the server:

```bash
# Any user can control the MCP server
echo '{"method":"shutdown"}' > /tmp/mcp_in.json
```

---

## Secure Alternatives

### Option 1: Named Pipes (FIFOs) - Recommended for Bash

**Security Level**: ⭐⭐⭐⭐ (Good)
**Complexity**: Low
**Performance**: High

Named pipes (FIFOs) provide:
- File system permissions control
- No file persistence (data exists only in transit)
- Blocking reads/writes prevent race conditions
- Can be placed in secure directories

#### Implementation Example

**Server Side** (`start_mcp_server_fifo.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common_config.sh"

# Use secure directory instead of /tmp
IPC_DIR="${PARROT_IPC_DIR:-/run/parrot-mcp}"
FIFO_PATH="$IPC_DIR/mcp.fifo"
LOG_FILE="$PARROT_SERVER_LOG"

# Initialize server
init_server() {
    # Create secure IPC directory
    if [ ! -d "$IPC_DIR" ]; then
        mkdir -p "$IPC_DIR"
        chmod 700 "$IPC_DIR"  # Owner only
    fi

    # Create named pipe
    if [ ! -p "$FIFO_PATH" ]; then
        mkfifo "$FIFO_PATH"
        chmod 600 "$FIFO_PATH"  # Owner read/write only
    fi

    parrot_info "MCP Server initialized with FIFO: $FIFO_PATH"
}

# Process messages
process_message() {
    local message="$1"

    # Validate JSON
    if ! echo "$message" | jq empty >/dev/null 2>&1; then
        parrot_error "Invalid JSON received"
        return 1
    fi

    # Validate message size
    local size=${#message}
    if [ "$size" -gt "$PARROT_MAX_INPUT_SIZE" ]; then
        parrot_error "Message exceeds maximum size: $size > $PARROT_MAX_INPUT_SIZE"
        return 1
    fi

    # Extract method
    local method
    method=$(echo "$message" | jq -r '.method // empty')

    case "$method" in
        ping)
            parrot_info "Received ping, responding with pong"
            echo '{"result": "pong"}'
            ;;
        *)
            parrot_warn "Unknown method: $method"
            echo '{"error": "Unknown method"}'
            ;;
    esac
}

# Main server loop
main() {
    init_server

    parrot_info "MCP Server listening on FIFO: $FIFO_PATH"

    # Read from FIFO (blocks until data available)
    while true; do
        if read -r message < "$FIFO_PATH"; then
            parrot_debug "Received message: $message"
            process_message "$message"
        fi
    done
}

# Cleanup on exit
cleanup() {
    parrot_info "Shutting down MCP Server"
    [ -p "$FIFO_PATH" ] && rm -f "$FIFO_PATH"
    [ -d "$IPC_DIR" ] && rmdir "$IPC_DIR" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

main
```

**Client Side** (sending messages):

```bash
#!/usr/bin/env bash
set -euo pipefail

IPC_DIR="/run/parrot-mcp"
FIFO_PATH="$IPC_DIR/mcp.fifo"

# Send message
send_message() {
    local message="$1"

    # Check if FIFO exists
    if [ ! -p "$FIFO_PATH" ]; then
        echo "ERROR: MCP Server not running (FIFO not found)" >&2
        return 1
    fi

    # Send message to FIFO (blocks if no reader)
    echo "$message" > "$FIFO_PATH"
}

# Usage
send_message '{"method":"ping","params":{}}'
```

#### Advantages of FIFOs

✅ **Secure by default**: Permissions enforced by filesystem
✅ **No persistence**: Data doesn't sit on disk
✅ **Blocking I/O**: Prevents race conditions
✅ **Pure Bash**: No external dependencies
✅ **Auditable**: File system events are logged

#### Limitations of FIFOs

⚠️ **Single reader**: Only one process can read from FIFO
⚠️ **Blocking**: Writers block if no reader present
⚠️ **Local only**: Cannot be used over network
⚠️ **No built-in encryption**: Data is plaintext in transit

---

### Option 2: Unix Domain Sockets - Best for Production

**Security Level**: ⭐⭐⭐⭐⭐ (Excellent)
**Complexity**: Medium (requires `socat` or language with socket support)
**Performance**: Very High

Unix domain sockets provide:
- All benefits of FIFOs
- Multiple concurrent clients
- Bidirectional communication
- Connection-based (detects disconnections)

#### Implementation with socat

**Server Side**:

```bash
#!/usr/bin/env bash
set -euo pipefail

IPC_DIR="/run/parrot-mcp"
SOCKET_PATH="$IPC_DIR/mcp.sock"

# Create secure directory
mkdir -p "$IPC_DIR"
chmod 700 "$IPC_DIR"

# Process function
process_connection() {
    while read -r message; do
        # Validate and process message
        if echo "$message" | jq empty >/dev/null 2>&1; then
            method=$(echo "$message" | jq -r '.method')
            case "$method" in
                ping) echo '{"result":"pong"}' ;;
                *) echo '{"error":"Unknown method"}' ;;
            esac
        else
            echo '{"error":"Invalid JSON"}'
        fi
    done
}

# Start server
socat UNIX-LISTEN:"$SOCKET_PATH",fork,mode=600 EXEC:"process_connection"
```

**Client Side**:

```bash
#!/usr/bin/env bash
set -euo pipefail

SOCKET_PATH="/run/parrot-mcp/mcp.sock"

# Send request and get response
send_request() {
    local request="$1"
    echo "$request" | socat - UNIX-CONNECT:"$SOCKET_PATH"
}

# Usage
response=$(send_request '{"method":"ping"}')
echo "Response: $response"
```

#### Implementation with Python (More Robust)

**Server** (`mcp_server.py`):

```python
#!/usr/bin/env python3
import socket
import os
import json
import logging

IPC_DIR = "/run/parrot-mcp"
SOCKET_PATH = f"{IPC_DIR}/mcp.sock"

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_message(data):
    """Process incoming MCP message."""
    try:
        message = json.loads(data)
        method = message.get('method')

        if method == 'ping':
            return {'result': 'pong'}
        else:
            return {'error': f'Unknown method: {method}'}

    except json.JSONDecodeError:
        return {'error': 'Invalid JSON'}

def main():
    # Create secure directory
    os.makedirs(IPC_DIR, mode=0o700, exist_ok=True)

    # Remove old socket if exists
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    # Create Unix domain socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(SOCKET_PATH)

    # Set secure permissions
    os.chmod(SOCKET_PATH, 0o600)

    sock.listen(5)
    logger.info(f"MCP Server listening on {SOCKET_PATH}")

    try:
        while True:
            conn, _ = sock.accept()
            try:
                data = conn.recv(4096).decode('utf-8')
                logger.debug(f"Received: {data}")

                response = process_message(data)
                conn.sendall(json.dumps(response).encode('utf-8'))

            except Exception as e:
                logger.error(f"Error processing message: {e}")
                conn.sendall(json.dumps({'error': str(e)}).encode('utf-8'))
            finally:
                conn.close()

    finally:
        sock.close()
        os.unlink(SOCKET_PATH)

if __name__ == '__main__':
    main()
```

**Client** (`mcp_client.py`):

```python
#!/usr/bin/env python3
import socket
import json
import sys

SOCKET_PATH = "/run/parrot-mcp/mcp.sock"

def send_request(request):
    """Send request to MCP server and return response."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    try:
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(request).encode('utf-8'))
        response = sock.recv(4096).decode('utf-8')
        return json.loads(response)

    finally:
        sock.close()

if __name__ == '__main__':
    request = {'method': 'ping', 'params': {}}
    response = send_request(request)
    print(f"Response: {response}")
```

#### Advantages of Unix Domain Sockets

✅ **Multiple clients**: Concurrent connections supported
✅ **Bidirectional**: Request/response pattern
✅ **Connection-aware**: Detect client disconnection
✅ **High performance**: Faster than network sockets
✅ **Secure**: Filesystem permissions + peer credentials
✅ **Standard protocol**: Well-understood, debuggable

---

### Option 3: Secure `/run` Directory (Interim Solution)

If you must continue using files temporarily, use `/run` instead of `/tmp`:

**Configuration** (`config.env`):

```bash
# Use /run instead of /tmp
PARROT_IPC_DIR="/run/parrot-mcp"
```

**Setup Script**:

```bash
#!/usr/bin/env bash
set -euo pipefail

IPC_DIR="/run/parrot-mcp"

# Create secure IPC directory
sudo mkdir -p "$IPC_DIR"
sudo chown "$USER:$USER" "$IPC_DIR"
sudo chmod 700 "$IPC_DIR"  # Owner only

echo "Secure IPC directory created: $IPC_DIR"
```

**Benefits over `/tmp`**:
- `/run` is typically tmpfs (RAM-based, cleared on reboot)
- Can set restrictive directory permissions
- Not world-writable by default
- OS-managed lifecycle

**Still Vulnerable To**:
- Race conditions
- No authentication
- File persistence (until reboot)

---

## Migration Path

### Phase 1: Secure Current Implementation (Immediate)

1. **Change IPC directory** from `/tmp` to `/run/parrot-mcp`:

```bash
# In config.env
PARROT_IPC_DIR="/run/parrot-mcp"
```

2. **Set restrictive permissions**:

```bash
chmod 700 /run/parrot-mcp
chmod 600 /run/parrot-mcp/*.json
```

3. **Add file locking**:

```bash
# Use flock to prevent race conditions
(
    flock -x 200
    cat /run/parrot-mcp/mcp_in.json
    rm /run/parrot-mcp/mcp_in.json
) 200>/run/parrot-mcp/mcp.lock
```

### Phase 2: Implement FIFOs (Short-term)

1. Create FIFO-based IPC (see implementation above)
2. Update server to use FIFOs
3. Update clients to write to FIFOs
4. Test thoroughly
5. Deprecate file-based IPC

**Timeline**: 1-2 weeks

### Phase 3: Migrate to Unix Domain Sockets (Long-term)

1. Implement Python-based server with Unix domain sockets
2. Provide Bash client wrapper for compatibility
3. Add authentication/authorization layer
4. Enable TLS for future network support
5. Remove FIFO implementation

**Timeline**: 1-3 months

---

## Security Best Practices

### 1. Use Secure Directories

**Do**:
- Use `/run/parrot-mcp` (RAM-based, cleared on reboot)
- Use `/var/lib/parrot-mcp` (persistent, system-managed)

**Don't**:
- Use `/tmp` (world-writable, shared)
- Use `/home/user` (exposed to user's other processes)

### 2. Set Restrictive Permissions

```bash
# Directory: Owner only
chmod 700 /run/parrot-mcp

# Files/FIFOs/Sockets: Owner read/write only
chmod 600 /run/parrot-mcp/mcp.fifo

# Verify permissions
stat -c "%a %U %G" /run/parrot-mcp/mcp.fifo
# Output: 600 parrot-mcp parrot-mcp
```

### 3. Run as Dedicated User

```bash
# Create dedicated user
sudo useradd -r -s /bin/bash -d /opt/parrot parrot-mcp

# Run server as that user
sudo -u parrot-mcp ./start_mcp_server.sh
```

### 4. Use AppArmor/SELinux

**AppArmor Profile** (`/etc/apparmor.d/usr.local.bin.mcp_server`):

```
#include <tunables/global>

/opt/parrot/rpi-scripts/start_mcp_server.sh {
    #include <abstractions/base>

    # IPC directory
    /run/parrot-mcp/ rw,
    /run/parrot-mcp/** rw,

    # Log directory
    /opt/parrot/logs/ rw,
    /opt/parrot/logs/** rw,

    # Deny network access
    deny network,

    # Deny sensitive files
    deny /etc/shadow r,
    deny /etc/passwd w,
}
```

### 5. Validate All Input

```bash
# Validate JSON before processing
validate_message() {
    local message="$1"

    # Check size
    if [ "${#message}" -gt "$PARROT_MAX_INPUT_SIZE" ]; then
        return 1
    fi

    # Validate JSON syntax
    if ! echo "$message" | jq empty >/dev/null 2>&1; then
        return 1
    fi

    # Validate message structure
    if ! echo "$message" | jq -e '.method' >/dev/null 2>&1; then
        return 1
    fi

    return 0
}
```

### 6. Implement Rate Limiting

```bash
# Simple rate limiting using nanoseconds
RATE_LIMIT=10  # messages per second
LAST_MESSAGE_TIME=0

check_rate_limit() {
    local now=$(date +%s%N)
    local elapsed=$((now - LAST_MESSAGE_TIME))
    local min_interval=$((1000000000 / RATE_LIMIT))  # nanoseconds between messages

    if [ "$elapsed" -lt "$min_interval" ]; then
        return 1  # Rate limit exceeded
    fi

    LAST_MESSAGE_TIME=$now
    return 0
}
```

### 7. Audit and Monitor

```bash
# Log all IPC activity
parrot_log "INFO" "IPC: Received message from client (size: ${#message})"

# Monitor for suspicious activity
inotifywait -m /run/parrot-mcp/ | while read -r event; do
    parrot_log "INFO" "IPC: File system event: $event"
done
```

---

## Testing Security

### Test 1: Permission Checks

```bash
# Create test user
sudo useradd -m testuser

# Try to access IPC as different user
sudo -u testuser cat /run/parrot-mcp/mcp.fifo
# Expected: Permission denied
```

### Test 2: Injection Attacks

```bash
# Try command injection
echo '{"method":"ping; rm -rf /"}' | send_request.sh
# Expected: Safely handled, command not executed
```

### Test 3: Path Traversal

```bash
# Try path traversal
echo '{"file":"../../../../etc/passwd"}' | send_request.sh
# Expected: Rejected by validation
```

### Test 4: Large Payload

```bash
# Generate large payload
python3 -c "print('{\"data\":\"' + 'A'*10000000 + '\"}')" | send_request.sh
# Expected: Rejected (exceeds PARROT_MAX_INPUT_SIZE)
```

---

## References

- [OWASP: Insecure Temporary File](https://owasp.org/www-community/vulnerabilities/Insecure_Temporary_File)
- [CWE-377: Insecure Temporary File](https://cwe.mitre.org/data/definitions/377.html)
- [Unix Domain Sockets Tutorial](https://man7.org/linux/man-pages/man7/unix.7.html)
- [Named Pipes (FIFOs)](https://man7.org/linux/man-pages/man7/fifo.7.html)

---

**Last Updated**: 2025-11-11
