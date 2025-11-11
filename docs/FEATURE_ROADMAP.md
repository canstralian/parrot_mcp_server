# Feature Implementation Roadmap

## Overview

This document provides a prioritized roadmap for implementing 11 proposed features for the Parrot MCP Server. Features are prioritized based on:
- **Security impact** (addressing critical vulnerabilities)
- **Foundation requirements** (dependencies for other features)
- **Current project maturity** (prototype status)
- **Implementation complexity vs. value**
- **Alignment with TODO.md and SECURITY.md**

**Last Updated**: 2025-11-11

---

## Priority Matrix

| Priority | Feature | Security Impact | Foundation | Complexity | Timeline |
|----------|---------|----------------|------------|-----------|----------|
| **P0** | #6 Secure Data Exchange | CRITICAL | Required | Medium | Week 1-2 |
| **P0** | #5 Role-based Access Control | HIGH | Required | Medium | Week 2-3 |
| **P1** | #8 Dynamic Config Reload | MEDIUM | Useful | Low | Week 3 |
| **P1** | #2 Event-driven Architecture | MEDIUM | Foundation | Medium | Week 4-5 |
| **P2** | #1 WebSocket Support | MEDIUM | Enhancement | High | Week 6-8 |
| **P2** | #3 Modular Extensions | LOW | Enhancement | Medium | Week 6-7 |
| **P3** | #4 Enhanced Monitoring | LOW | Operational | Medium | Week 8-9 |
| **P3** | #10 CI/CD Enhancement | LOW | DevOps | Low | Week 9-10 |
| **P4** | #7 Multi-language Bindings | LOW | Ecosystem | High | Month 3-4 |
| **P5** | #9 Auto-scaling | LOW | Premature | High | Month 6+ |
| **P5** | #11 Localization | LOW | Nice-to-have | Medium | Month 6+ |

---

## Phase 1: Security Foundation (Weeks 1-3)

### Feature #6: Secure Data Exchange ⭐ CRITICAL PRIORITY

**Status**: Addresses TODO.md item #1 and SECURITY.md critical vulnerability #1

**Problem**:
- Current IPC uses `/tmp/mcp_in.json` (world-readable, race conditions, symlink attacks)
- No encryption for sensitive data
- Predictable file paths

**Implementation Plan**:

#### Week 1: Migrate to Secure IPC

**Option A: Named Pipes (FIFOs)** - Recommended for pure Bash
```bash
# Benefits:
- ✅ Pure Bash (no dependencies)
- ✅ No file persistence
- ✅ Blocking I/O prevents race conditions
- ✅ Filesystem permissions control access
- ✅ Low complexity

# Limitations:
- ⚠️ Single reader limitation
- ⚠️ Local-only (no network)
- ⚠️ No built-in encryption
```

**Implementation**:
1. Create `/run/parrot-mcp/` directory with 700 permissions
2. Implement `rpi-scripts/start_mcp_server_fifo.sh` (see docs/IPC_SECURITY.md:112-204)
3. Update `common_config.sh` with FIFO configuration variables
4. Add FIFO client wrapper `rpi-scripts/mcp_client.sh`
5. Update `test_mcp_local.sh` to test FIFO communication
6. Add BATS tests in `tests/ipc_security.bats`

**Option B: Unix Domain Sockets** - Best for production
```bash
# Benefits:
- ✅ Multiple concurrent clients
- ✅ Bidirectional communication
- ✅ Connection-aware (detects disconnects)
- ✅ Better performance
- ✅ Standard protocol

# Requirements:
- Requires `socat` or Python/Go implementation
- Higher complexity
```

**Implementation**:
1. Create Python-based server `rpi-scripts/mcp_server.py` (see docs/IPC_SECURITY.md:318-388)
2. Create Python client `rpi-scripts/mcp_client.py`
3. Create Bash wrapper `rpi-scripts/cli_socket.sh` for backward compatibility
4. Update systemd service file
5. Add socket activation support

**Recommendation**: Start with FIFOs (Week 1), migrate to Unix sockets (Week 2-3)

#### Week 2: Add Message Encryption

**For sensitive payloads only** (optional encryption layer):

```bash
# GPG-based encryption
encrypt_message() {
    local message="$1"
    local recipient_key="$PARROT_GPG_KEY"

    echo "$message" | gpg --encrypt --armor --recipient "$recipient_key"
}

decrypt_message() {
    local encrypted="$1"
    echo "$encrypted" | gpg --decrypt
}
```

**Configuration** (`config.env`):
```bash
# Encryption settings
PARROT_ENCRYPTION_ENABLED=false  # Default: disabled
PARROT_GPG_KEY=""                # GPG recipient key ID
PARROT_ENCRYPTION_ALGORITHM="AES256"
```

**Deliverables**:
- [ ] FIFO-based IPC implementation
- [ ] `/run/parrot-mcp/` secure directory setup
- [ ] Client wrapper scripts
- [ ] Optional GPG encryption layer
- [ ] Migration guide from file-based IPC
- [ ] BATS test suite for secure IPC
- [ ] Updated SECURITY.md with mitigation status

---

### Feature #5: Role-based Access Control (RBAC) ⭐ HIGH PRIORITY

**Status**: Addresses SECURITY.md critical vulnerability #3

**Problem**:
- No authentication/authorization
- Any local process can send MCP messages
- No access control for different operations

**Implementation Plan**:

#### Week 2-3: Implement RBAC Framework

**1. Define Roles** (`rpi-scripts/rbac_roles.json`):
```json
{
  "roles": {
    "admin": {
      "description": "Full system access",
      "permissions": ["*"]
    },
    "operator": {
      "description": "Can execute operations, view status",
      "permissions": ["mcp:execute", "mcp:read", "health:check", "logs:read"]
    },
    "viewer": {
      "description": "Read-only access",
      "permissions": ["mcp:read", "health:check", "logs:read"]
    },
    "cron": {
      "description": "Automated task execution",
      "permissions": ["daily_workflow:execute", "backup:execute", "system_update:execute"]
    }
  }
}
```

**2. User Configuration** (`rpi-scripts/rbac_users.json`):
```json
{
  "users": {
    "pi": {
      "roles": ["admin"],
      "api_key_hash": "$2b$12$...",
      "created": "2025-11-11T00:00:00Z"
    },
    "automation": {
      "roles": ["cron"],
      "api_key_hash": "$2b$12$...",
      "created": "2025-11-11T00:00:00Z"
    }
  }
}
```

**3. Permission Checking** (`rpi-scripts/rbac.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common_config.sh"

RBAC_ROLES_FILE="${PARROT_RBAC_ROLES_FILE:-$SCRIPT_DIR/rbac_roles.json}"
RBAC_USERS_FILE="${PARROT_RBAC_USERS_FILE:-$SCRIPT_DIR/rbac_users.json}"

# Check if user has permission
rbac_check_permission() {
    local user="$1"
    local permission="$2"

    # Get user roles
    local roles
    roles=$(jq -r ".users[\"$user\"].roles[]" "$RBAC_USERS_FILE" 2>/dev/null || echo "")

    if [ -z "$roles" ]; then
        parrot_error "User '$user' not found"
        return 1
    fi

    # Check each role for permission
    while IFS= read -r role; do
        local perms
        perms=$(jq -r ".roles[\"$role\"].permissions[]" "$RBAC_ROLES_FILE" 2>/dev/null || echo "")

        # Check for wildcard or exact match
        while IFS= read -r perm; do
            if [ "$perm" = "*" ] || [ "$perm" = "$permission" ]; then
                return 0
            fi
        done <<< "$perms"
    done <<< "$roles"

    parrot_warn "User '$user' denied permission: $permission"
    return 1
}

# Authenticate user by API key
rbac_authenticate() {
    local api_key="$1"

    # Hash the provided API key
    local key_hash
    key_hash=$(echo -n "$api_key" | sha256sum | awk '{print $1}')

    # Find user with matching API key hash
    local user
    user=$(jq -r --arg hash "$key_hash" \
        '.users | to_entries[] | select(.value.api_key_hash == $hash) | .key' \
        "$RBAC_USERS_FILE" 2>/dev/null || echo "")

    if [ -z "$user" ]; then
        parrot_error "Authentication failed: Invalid API key"
        return 1
    fi

    echo "$user"
    return 0
}

# Generate new API key
rbac_generate_api_key() {
    openssl rand -hex 32
}

# Hash API key for storage
rbac_hash_api_key() {
    local api_key="$1"
    echo -n "$api_key" | sha256sum | awk '{print $1}'
}
```

**4. Integration with MCP Server**:
```bash
# In start_mcp_server.sh
process_message() {
    local message="$1"

    # Extract API key from message
    local api_key
    api_key=$(echo "$message" | jq -r '.auth.api_key // empty')

    # Authenticate
    local user
    user=$(rbac_authenticate "$api_key") || {
        echo '{"error":"Authentication failed"}'
        return 1
    }

    # Extract method
    local method
    method=$(echo "$message" | jq -r '.method')

    # Check permission
    rbac_check_permission "$user" "mcp:execute:$method" || {
        echo '{"error":"Permission denied"}'
        return 1
    }

    # Process message...
}
```

**5. API Key Management Tool** (`rpi-scripts/rbac_admin.sh`):
```bash
#!/usr/bin/env bash
# Usage: ./rbac_admin.sh create-user <username> <role>
# Usage: ./rbac_admin.sh revoke-user <username>
# Usage: ./rbac_admin.sh list-users
```

**Configuration** (`config.env`):
```bash
# RBAC settings
PARROT_RBAC_ENABLED=true
PARROT_RBAC_ROLES_FILE="$SCRIPT_DIR/rbac_roles.json"
PARROT_RBAC_USERS_FILE="$SCRIPT_DIR/rbac_users.json"
PARROT_RBAC_STRICT_MODE=true  # Deny by default
```

**Deliverables**:
- [ ] RBAC role definition schema
- [ ] RBAC user management system
- [ ] Permission checking library (`rbac.sh`)
- [ ] API key authentication
- [ ] Admin CLI tool (`rbac_admin.sh`)
- [ ] Integration with MCP server
- [ ] BATS tests for RBAC
- [ ] Documentation in SECURITY.md

---

### Feature #8: Dynamic Configuration Reload ⭐ MEDIUM PRIORITY

**Status**: Operational improvement, enables zero-downtime config changes

**Problem**:
- Server restart required for config changes
- Downtime during testing/development
- No hot-reload capability

**Implementation Plan**:

#### Week 3: Implement Config Reload

**1. Signal-based Reload** (using `trap`):
```bash
# In start_mcp_server.sh
reload_config() {
    parrot_info "Reloading configuration..."

    # Re-source common_config.sh
    source "$SCRIPT_DIR/common_config.sh"

    # Reload role/permission files
    if [ "$PARROT_RBAC_ENABLED" = "true" ]; then
        source "$SCRIPT_DIR/rbac.sh"
    fi

    # Reload logging configuration
    PARROT_CURRENT_LOG="$PARROT_SERVER_LOG"

    parrot_info "Configuration reloaded successfully"
}

# Trap SIGHUP for config reload
trap 'reload_config' HUP
```

**2. Inotify-based Auto-reload** (watches config files):
```bash
#!/usr/bin/env bash
# config_watcher.sh - Background process to monitor config changes

watch_config() {
    local config_file="$PARROT_CONFIG_FILE"

    inotifywait -m -e modify "$config_file" | while read -r event; do
        parrot_info "Config file changed, sending reload signal..."

        # Send SIGHUP to MCP server
        local pid
        pid=$(cat "$PARROT_PID_FILE" 2>/dev/null)

        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -HUP "$pid"
        fi
    done
}
```

**3. Runtime Config API**:
```bash
# Add "reload_config" method to MCP protocol
{
  "method": "reload_config",
  "params": {
    "modules": ["logging", "rbac", "ipc"]
  }
}
```

**Configuration** (`config.env`):
```bash
# Config reload settings
PARROT_CONFIG_WATCH_ENABLED=false  # Auto-reload on file change
PARROT_CONFIG_RELOAD_SIGNAL="HUP"  # Signal to trigger reload
```

**CLI Support**:
```bash
# Reload via CLI
./cli.sh reload-config

# Reload specific module
./cli.sh reload-config --module=logging
```

**Deliverables**:
- [ ] Signal-based config reload (SIGHUP)
- [ ] Inotify-based auto-reload
- [ ] MCP method for remote reload
- [ ] CLI command for reload
- [ ] Validation before reload (test config syntax)
- [ ] Rollback on invalid config
- [ ] BATS tests for reload scenarios
- [ ] Documentation in CONFIGURATION.md

---

## Phase 2: Architecture Foundation (Weeks 4-5)

### Feature #2: Event-driven Architecture ⭐ MEDIUM PRIORITY

**Status**: Foundation for scalability, addresses responsiveness concerns

**Problem**:
- Current server is synchronous (blocking)
- Poor handling of concurrent requests
- Limited scalability
- No event tracing/debugging

**Implementation Plan**:

#### Week 4-5: Implement Event System

**1. Event Schema** (`events/event_schema.json`):
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["event_type", "timestamp", "payload"],
  "properties": {
    "event_type": {
      "type": "string",
      "enum": [
        "SERVER_STARTED",
        "SERVER_STOPPED",
        "MESSAGE_RECEIVED",
        "MESSAGE_PROCESSED",
        "ERROR_OCCURRED",
        "CONFIG_RELOADED",
        "CLIENT_CONNECTED",
        "CLIENT_DISCONNECTED",
        "HEALTH_CHECK_COMPLETED",
        "BACKUP_COMPLETED"
      ]
    },
    "timestamp": {
      "type": "string",
      "format": "date-time"
    },
    "payload": {
      "type": "object"
    },
    "metadata": {
      "type": "object",
      "properties": {
        "source": { "type": "string" },
        "correlation_id": { "type": "string" }
      }
    }
  }
}
```

**2. Event Bus** (`rpi-scripts/event_bus.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common_config.sh"

EVENT_LOG="${PARROT_EVENT_LOG:-$PARROT_LOG_DIR/events.log}"
EVENT_SUBSCRIBERS=()

# Emit an event
event_emit() {
    local event_type="$1"
    shift
    local payload="$*"

    # Create event structure
    local event
    event=$(jq -n \
        --arg type "$event_type" \
        --arg timestamp "$(date -Iseconds)" \
        --arg payload "$payload" \
        '{
            event_type: $type,
            timestamp: $timestamp,
            payload: $payload,
            metadata: {
                source: "mcp_server",
                correlation_id: env.PARROT_CORRELATION_ID // ""
            }
        }')

    # Log event
    echo "$event" >> "$EVENT_LOG"
    parrot_debug "Event emitted: $event_type"

    # Notify subscribers (call handler functions)
    for subscriber in "${EVENT_SUBSCRIBERS[@]}"; do
        "$subscriber" "$event_type" "$payload" &
    done
}

# Subscribe to events
event_subscribe() {
    local handler="$1"
    EVENT_SUBSCRIBERS+=("$handler")
}

# Dispatch event to handlers
event_dispatch() {
    local event_type="$1"
    shift
    local payload="$*"

    case "$event_type" in
        MESSAGE_RECEIVED)
            handle_message "$payload"
            ;;
        SERVER_STARTED)
            handle_server_started
            ;;
        ERROR_OCCURRED)
            handle_error "$payload"
            notify_admin "$payload"
            ;;
        CONFIG_RELOADED)
            handle_config_reloaded
            ;;
        HEALTH_CHECK_COMPLETED)
            handle_health_check "$payload"
            ;;
        *)
            parrot_warn "Unknown event type: $event_type"
            ;;
    esac
}

# Event handlers
handle_message() {
    local message="$1"
    parrot_info "Processing message: $message"
    # Message processing logic
    event_emit "MESSAGE_PROCESSED" "$message"
}

handle_error() {
    local error="$1"
    parrot_error "Error occurred: $error"
}

handle_server_started() {
    parrot_info "Server started successfully"
}

handle_config_reloaded() {
    parrot_info "Configuration reloaded"
}

handle_health_check() {
    local result="$1"
    parrot_info "Health check completed: $result"
}
```

**3. Async Event Processing** (background tasks):
```bash
# Process events asynchronously
process_event_async() {
    local event="$1"

    # Run in background
    (
        event_dispatch "$event" &
    )
}

# Event queue using named pipe
EVENT_QUEUE="/run/parrot-mcp/event.fifo"

# Event worker process
event_worker() {
    while read -r event < "$EVENT_QUEUE"; do
        process_event_async "$event"
    done
}

# Start event worker in background
event_worker &
```

**4. Integration with Server**:
```bash
# In start_mcp_server.sh
source "$SCRIPT_DIR/event_bus.sh"

# Subscribe handlers
event_subscribe "handle_message"
event_subscribe "handle_error"

# Emit events
event_emit "SERVER_STARTED" "{\"pid\":$$,\"version\":\"$PARROT_VERSION\"}"

while true; do
    if read -r message < "$FIFO_PATH"; then
        event_emit "MESSAGE_RECEIVED" "$message"
    fi
done
```

**5. Event Monitoring Dashboard** (CLI):
```bash
#!/usr/bin/env bash
# event_monitor.sh - Real-time event stream viewer

tail -f "$PARROT_EVENT_LOG" | jq -r \
    '[.timestamp, .event_type, .payload] | @tsv'
```

**Configuration** (`config.env`):
```bash
# Event system settings
PARROT_EVENT_LOG="$PARROT_LOG_DIR/events.log"
PARROT_EVENT_ASYNC=true          # Process events in background
PARROT_EVENT_PERSISTENCE=true    # Store events to disk
PARROT_EVENT_RETENTION_DAYS=30   # Keep events for 30 days
```

**Deliverables**:
- [ ] Event schema definition
- [ ] Event bus implementation
- [ ] Event dispatcher with handlers
- [ ] Async event processing
- [ ] Event queue (FIFO-based)
- [ ] Event monitoring CLI tool
- [ ] Integration with MCP server
- [ ] BATS tests for event system
- [ ] Documentation in new EVENTS.md

---

## Phase 3: Enhanced Capabilities (Weeks 6-10)

### Feature #1: WebSocket Communication Support

**Priority**: P2 (Week 6-8)
**Dependencies**: #6 (Secure IPC), #2 (Event-driven Architecture)

**Implementation**: Use Python with `websockets` library or Node.js with `ws`

**Deliverables**:
- [ ] WebSocket server implementation
- [ ] TLS/WSS support
- [ ] Message protocol (JSON-RPC over WebSocket)
- [ ] Client library (Python/JavaScript)
- [ ] Backward compatibility with file/FIFO IPC
- [ ] Connection pooling and management
- [ ] Rate limiting per connection
- [ ] Docs in WEBSOCKET.md

---

### Feature #3: Plug-and-play Modular Extensions

**Priority**: P2 (Week 6-7)
**Dependencies**: None (plugin system already partially exists)

**Current State**:
- ✅ Script discovery via `cli.sh`
- ✅ `scripts/` directory convention
- ⚠️ No formal plugin API
- ⚠️ No plugin metadata
- ⚠️ No dependency management

**Enhancement Plan**:

**1. Plugin Manifest** (`scripts/hello/manifest.json`):
```json
{
  "name": "hello",
  "version": "1.0.0",
  "description": "Example Hello World plugin",
  "author": "Parrot MCP Contributors",
  "entrypoint": "hello.sh",
  "permissions": ["logs:write"],
  "dependencies": [],
  "config": {
    "HELLO_MESSAGE": {
      "type": "string",
      "default": "Hello, World!",
      "description": "Message to display"
    }
  }
}
```

**2. Plugin API** (`rpi-scripts/plugin_api.sh`):
```bash
# Standardized plugin interface
plugin_init() {
    local plugin_dir="$1"

    # Load manifest
    local manifest="$plugin_dir/manifest.json"

    # Validate permissions
    # Load dependencies
    # Initialize plugin
}

plugin_execute() {
    local plugin_name="$1"
    shift

    # Check if plugin is enabled
    # Validate permissions
    # Execute plugin entrypoint
}
```

**3. Plugin Manager** (`cli.sh plugin` subcommand):
```bash
# List plugins
./cli.sh plugin list

# Enable/disable plugins
./cli.sh plugin enable hello
./cli.sh plugin disable hello

# Install plugin from repo
./cli.sh plugin install https://github.com/user/parrot-plugin-example
```

**Deliverables**:
- [ ] Plugin manifest schema
- [ ] Plugin API library
- [ ] Plugin manager CLI
- [ ] Plugin repository structure
- [ ] Example plugins (3-5 examples)
- [ ] Plugin development guide
- [ ] BATS tests for plugin system
- [ ] Docs in PLUGINS.md

---

### Feature #4: Enhanced Monitoring and Dashboards

**Priority**: P3 (Week 8-9)

**Implementation Options**:

**Option A: CLI Dashboard** (ncurses/bash):
```bash
#!/usr/bin/env bash
# dashboard.sh - Real-time CLI monitoring

while true; do
    clear
    echo "=== Parrot MCP Server Dashboard ==="
    echo "Status: $(systemctl is-active parrot-mcp)"
    echo "Uptime: $(systemctl show -p ActiveEnterTimestamp parrot-mcp)"
    echo ""
    echo "=== Recent Events ==="
    tail -n 5 "$PARROT_EVENT_LOG" | jq -r '.event_type'
    echo ""
    echo "=== System Health ==="
    ./cli.sh health_check --quiet
    sleep 2
done
```

**Option B: Web Dashboard** (lightweight Flask/FastAPI):
```python
from flask import Flask, render_template, jsonify
import json

app = Flask(__name__)

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/status')
def status():
    # Read logs and return metrics
    return jsonify({
        'server_status': 'running',
        'uptime': 12345,
        'message_count': 100,
        'error_count': 2
    })
```

**Deliverables**:
- [ ] CLI dashboard tool
- [ ] Optional web dashboard
- [ ] Metrics collection (Prometheus format)
- [ ] Log aggregation viewer
- [ ] Performance metrics (latency, throughput)
- [ ] Alert integration
- [ ] Docs in MONITORING.md

---

### Feature #10: CI/CD Enhanced Integration

**Priority**: P3 (Week 9-10)

**Current State**:
- ✅ Basic ShellCheck linting
- ✅ Sanity testing
- ✅ Multi-platform builds (Ubuntu, macOS)
- ⚠️ BATS tests exist but not run in CI
- ⚠️ No code coverage
- ⚠️ No security scanning

**Enhancement Plan**:

**.github/workflows/test-enhanced.yml**:
```yaml
name: Enhanced Testing

on: [push, pull_request]

jobs:
  bats-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install BATS
        run: |
          sudo apt-get install -y bats
          sudo npm install -g bats-support bats-assert
      - name: Run BATS tests
        run: |
          cd rpi-scripts/tests
          bats *.bats

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'

  code-coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install kcov
        run: sudo apt-get install -y kcov
      - name: Generate coverage
        run: |
          kcov --include-path=./rpi-scripts coverage ./rpi-scripts/test_mcp_local.sh
      - name: Upload to Codecov
        uses: codecov/codecov-action@v3

  build-multi-arch:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        arch: [amd64, arm64, armv7]
    steps:
      - uses: actions/checkout@v4
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
      - name: Build for ${{ matrix.arch }}
        run: |
          # Package scripts for target architecture
          tar -czf parrot-mcp-${{ matrix.arch }}.tar.gz rpi-scripts/
```

**Deliverables**:
- [ ] BATS test execution in CI
- [ ] Code coverage reporting (Codecov/Coveralls)
- [ ] Security scanning (Trivy, Snyk)
- [ ] Multi-architecture builds (ARM64, ARMv7, AMD64)
- [ ] Automated releases (GitHub Releases)
- [ ] Deployment templates (Docker, systemd)
- [ ] Pre-commit hooks configuration

---

## Phase 4: Ecosystem Expansion (Month 3-6)

### Feature #7: Multi-language Bindings for Clients

**Priority**: P4 (Month 3-4)

**Languages**: Python, JavaScript/TypeScript, Go, Rust

**Python Client Example**:
```python
# parrot_mcp/client.py
import socket
import json

class ParrotMCPClient:
    def __init__(self, socket_path="/run/parrot-mcp/mcp.sock"):
        self.socket_path = socket_path

    def send_message(self, method, params=None):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(self.socket_path)

        message = {
            "method": method,
            "params": params or {}
        }

        sock.sendall(json.dumps(message).encode())
        response = sock.recv(4096).decode()
        sock.close()

        return json.loads(response)

    def ping(self):
        return self.send_message("ping")
```

**Deliverables**:
- [ ] Python client library (PyPI package)
- [ ] JavaScript/TypeScript client (npm package)
- [ ] Go client library
- [ ] Rust client library
- [ ] Client documentation per language
- [ ] Example applications
- [ ] Integration tests

---

### Feature #9: Auto-scaling Support

**Priority**: P5 (Month 6+)
**Status**: Premature for current prototype phase

**Recommendation**: Defer until:
- Core MCP functionality is complete
- Production deployments exist
- Actual scaling requirements identified

---

### Feature #11: Language Localization Support

**Priority**: P5 (Month 6+)
**Status**: Nice-to-have, not critical

**Recommendation**: Defer until user base justifies localization effort

---

## Implementation Schedule

### Sprint 1-2 (Weeks 1-3): Security Foundation
- ✅ Secure IPC (FIFOs/Unix sockets)
- ✅ RBAC implementation
- ✅ Dynamic config reload

### Sprint 3 (Weeks 4-5): Architecture
- ✅ Event-driven architecture

### Sprint 4-5 (Weeks 6-9): Enhanced Capabilities
- ✅ WebSocket support
- ✅ Modular extensions
- ✅ Monitoring dashboard

### Sprint 6 (Weeks 9-10): DevOps
- ✅ CI/CD enhancements

### Future (Month 3+): Ecosystem
- Multi-language bindings
- Auto-scaling (deferred)
- Localization (deferred)

---

## Success Metrics

### Phase 1 (Security)
- [ ] Zero critical security vulnerabilities
- [ ] All TODO.md security items resolved
- [ ] SECURITY.md updated with mitigations
- [ ] BATS test coverage >80%

### Phase 2 (Architecture)
- [ ] Event processing latency <100ms
- [ ] Support 10+ concurrent clients
- [ ] Zero message loss under load

### Phase 3 (Capabilities)
- [ ] WebSocket support with TLS
- [ ] 5+ community plugins available
- [ ] Dashboard showing real-time metrics

---

## Decision Log

### Why FIFOs before Unix Sockets?
- Lower complexity for Bash-first approach
- Meets security requirements
- Easier testing and debugging
- Migration path to sockets is clear

### Why Event-driven Architecture in Phase 2?
- Requires secure foundation first
- Enables future scalability features
- Complex enough to deserve focused effort

### Why defer Auto-scaling?
- Project is prototype/experimental
- No production deployments yet
- Premature optimization
- Can revisit after Month 6

### Why RBAC before WebSocket?
- Security-first approach
- WebSocket without auth is dangerous
- RBAC can be used for file/FIFO IPC too

---

## Next Steps

1. **Review and approve roadmap** with project maintainers
2. **Create GitHub Issues** for each feature (11 issues)
3. **Create Milestones** for each sprint
4. **Assign priorities** and owners
5. **Start with Feature #6** (Secure Data Exchange)

---

**Document Maintenance**:
- Update priority as features are completed
- Track implementation status in checkboxes
- Link to related GitHub Issues/PRs
- Review quarterly for alignment

**Last Updated**: 2025-11-11
**Next Review**: 2025-12-11
