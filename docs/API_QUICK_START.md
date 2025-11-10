# API Integration Quick Start

Get started with Parrot MCP Server API integrations in 5 minutes.

---

## Prerequisites

```bash
# Install required tools (if not already installed)
sudo apt-get install curl jq netcat-openbsd  # Debian/Ubuntu
# Or
brew install curl jq netcat  # macOS
```

---

## Quick Start Guide

### 1. Set Up Environment

```bash
# Clone repository
git clone https://github.com/canstralian/parrot_mcp_server.git
cd parrot_mcp_server

# Copy environment template
cp .env.example .env

# Edit .env and add your API keys (optional for basic testing)
nano .env
```

### 2. Test JSON-RPC (MCP Protocol)

```bash
cd rpi-scripts

# Test ping
echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' > /tmp/ping.json
./scripts/mcp_jsonrpc.sh /tmp/ping.json /tmp/response.json
cat /tmp/response.json | jq

# Output: {"jsonrpc":"2.0","id":"1","result":"pong"}
```

### 3. Process Webhooks

```bash
# Create test webhook
echo '{"type":"mcp_message","method":"ping","id":1}' > /tmp/webhook.json

# Process it
./scripts/process_webhook.sh /tmp/webhook.json

# Check logs
tail logs/parrot.log
```

### 4. Make API Calls

```bash
# GET request
./scripts/api_client.sh GET "https://api.github.com/repos/canstralian/parrot_mcp_server"

# POST request
./scripts/api_client.sh POST \
  "https://httpbin.org/post" \
  '{"test":"data"}' \
  "Content-Type: application/json"
```

### 5. Send Notifications (Optional)

```bash
# Set webhook URL
export SLACK_WEBHOOK_URL="your_webhook_url"

# Send notification
./scripts/notify_slack.sh "Hello from Parrot MCP Server! 🦜"
```

---

## Common Use Cases

### Receive GitHub Webhooks

```bash
# Start webhook receiver
./scripts/webhook_receiver.sh 8080 ./scripts/process_webhook.sh &

# Configure GitHub webhook to POST to:
# http://your-server:8080/webhook
```

### Call MCP Tools

```bash
# Health check
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"health_check"}}' | \
  ./scripts/mcp_jsonrpc.sh /dev/stdin /dev/stdout | jq

# Disk check
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"check_disk"}}' | \
  ./scripts/mcp_jsonrpc.sh /dev/stdin /dev/stdout | jq
```

### Automated Workflow

```bash
#!/usr/bin/env bash
# Daily health check with Slack notification

# Load environment
export $(grep -v '^#' .env | xargs)

# Run health check
RESULT=$(echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"health_check"}}' | \
  ./scripts/mcp_jsonrpc.sh /dev/stdin /dev/stdout | jq -r '.result.content[0].text')

# Send to Slack
./scripts/notify_slack.sh "Daily Health Check:\n$RESULT"
```

---

## Testing

```bash
# Run existing tests
./test_mcp_local.sh

# Run API integration tests (requires bats)
bats tests/api_integration.bats

# Validate scripts
shellcheck scripts/*.sh
```

---

## Troubleshooting

### Webhook receiver not working?
```bash
# Check if port is available
netstat -tuln | grep 8080

# Check if nc (netcat) is installed
which nc
```

### JSON-RPC errors?
```bash
# Validate your JSON
echo '{"your":"json"}' | jq empty

# Check logs for details
grep ERROR logs/parrot.log
```

### API calls failing?
```bash
# Test network connectivity
curl -I https://api.github.com

# Check if curl is installed
which curl
```

---

## Next Steps

- Read [API_INTEGRATIONS.md](./API_INTEGRATIONS.md) for detailed patterns
- See [API_EXAMPLES.md](./API_EXAMPLES.md) for comprehensive examples
- Review [API_INTEGRATION_SUMMARY.md](./API_INTEGRATION_SUMMARY.md) for implementation details

---

## Quick Command Reference

| Task | Command |
|------|---------|
| Test JSON-RPC ping | `echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' \| ./scripts/mcp_jsonrpc.sh /dev/stdin /dev/stdout` |
| Start webhook receiver | `./scripts/webhook_receiver.sh 8080 ./scripts/process_webhook.sh &` |
| Process webhook file | `./scripts/process_webhook.sh webhook.json` |
| GET API request | `./scripts/api_client.sh GET "https://api.example.com"` |
| POST API request | `./scripts/api_client.sh POST "url" '{"data":"value"}'` |
| Send Slack notification | `./scripts/notify_slack.sh "message"` |
| Check logs | `tail -f logs/parrot.log` |
| Run tests | `./test_mcp_local.sh` |
| Validate scripts | `shellcheck scripts/*.sh` |

---

**Need help?** Open an issue at https://github.com/canstralian/parrot_mcp_server/issues
