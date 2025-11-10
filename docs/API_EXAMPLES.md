# API Integration Examples

This document provides practical examples for using the Parrot MCP Server's API integration features.

---

## Quick Start

### 1. Set Up Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and add your API keys
nano .env
```

### 2. Load Environment Variables

```bash
# Load environment variables into your shell
export $(grep -v '^#' .env | xargs)
```

---

## Example 1: Receiving Webhooks

Start the webhook receiver to listen for incoming HTTP requests:

```bash
# Start webhook receiver on port 8080
./rpi-scripts/scripts/webhook_receiver.sh 8080 ./rpi-scripts/scripts/process_webhook.sh &

# Get the PID for later cleanup
WEBHOOK_PID=$!
```

Send a test webhook:

```bash
# Send a test MCP message via webhook
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{"type":"mcp_message","method":"ping","id":1}'

# Send a GitHub-style webhook
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{"type":"github_webhook","action":"push","repository":"test/repo"}'
```

Stop the webhook receiver:

```bash
kill $WEBHOOK_PID
```

---

## Example 2: JSON-RPC Message Processing

Process MCP messages using the JSON-RPC handler:

```bash
# Create a JSON-RPC request
cat > request.json <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "health_check",
    "arguments": {}
  }
}
EOF

# Process the request
./rpi-scripts/scripts/mcp_jsonrpc.sh request.json response.json

# View the response
cat response.json | jq
```

### Example Requests

**Ping Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "ping"
}
```

**Tool Call Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "check_disk",
    "arguments": {}
  }
}
```

---

## Example 3: Making REST API Calls

### GET Request

```bash
# Make a simple GET request
./rpi-scripts/scripts/api_client.sh GET "https://api.github.com/repos/canstralian/parrot_mcp_server"

# With custom headers
./rpi-scripts/scripts/api_client.sh GET "https://api.example.com/data" "" "Authorization: Bearer YOUR_TOKEN"
```

### POST Request

```bash
# Make a POST request with JSON data
./rpi-scripts/scripts/api_client.sh POST \
  "https://api.example.com/scan" \
  '{"target":"192.168.1.1","type":"port-scan"}' \
  "Content-Type: application/json"
```

---

## Example 4: Slack Notifications

Send notifications to Slack:

```bash
# Set your Slack webhook URL
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Send a simple notification
./rpi-scripts/scripts/notify_slack.sh "MCP Server health check passed ✅"

# Send with a specific channel
./rpi-scripts/scripts/notify_slack.sh "Security alert detected!" "#security-alerts"
```

### Integrate with Other Scripts

```bash
# Send notification after health check
if ./rpi-scripts/scripts/health_check.sh; then
    ./rpi-scripts/scripts/notify_slack.sh "✅ Health check passed"
else
    ./rpi-scripts/scripts/notify_slack.sh "❌ Health check failed!"
fi
```

---

## Example 5: GitHub API Integration

Query GitHub API for repository information:

```bash
# Set your GitHub token
export GITHUB_TOKEN="ghp_your_token"

# Get repository info
./rpi-scripts/scripts/api_client.sh GET \
  "https://api.github.com/repos/canstralian/parrot_mcp_server" \
  "" \
  "Authorization: token $GITHUB_TOKEN"

# List issues
./rpi-scripts/scripts/api_client.sh GET \
  "https://api.github.com/repos/canstralian/parrot_mcp_server/issues" \
  "" \
  "Authorization: token $GITHUB_TOKEN"
```

---

## Example 6: Automated Workflow

Create an automated workflow that combines multiple integrations:

```bash
#!/usr/bin/env bash
# automated_workflow.sh - Example automated security workflow

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Run health check
echo "Running health check..."
HEALTH_RESULT=$(./rpi-scripts/scripts/health_check.sh 2>&1)

# Check disk space
echo "Checking disk space..."
DISK_RESULT=$(./rpi-scripts/scripts/check_disk.sh 2>&1)

# Create report
REPORT="📊 Daily Report\n\n"
REPORT+="Health Check:\n$HEALTH_RESULT\n\n"
REPORT+="Disk Space:\n$DISK_RESULT"

# Send to Slack
./rpi-scripts/scripts/notify_slack.sh "$REPORT"

# Create GitHub issue if disk space is low
if echo "$DISK_RESULT" | grep -q "WARNING"; then
    ISSUE_BODY='{"title":"Low Disk Space Warning","body":"Automated alert: Disk space is running low"}'
    ./rpi-scripts/scripts/api_client.sh POST \
      "https://api.github.com/repos/canstralian/parrot_mcp_server/issues" \
      "$ISSUE_BODY" \
      "Authorization: token $GITHUB_TOKEN;Content-Type: application/json"
fi
```

---

## Example 7: OpenAI Integration

Query OpenAI API for AI-powered analysis:

```bash
# Set your OpenAI API key
export OPENAI_API_KEY="sk-your_key"

# Analyze scan results with GPT-4
SCAN_OUTPUT=$(cat scan_results.txt)

PROMPT="Analyze this security scan output and summarize the findings:\n\n$SCAN_OUTPUT"

./rpi-scripts/scripts/api_client.sh POST \
  "https://api.openai.com/v1/chat/completions" \
  "{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}" \
  "Authorization: Bearer $OPENAI_API_KEY;Content-Type: application/json"
```

---

## Example 8: Webhook Integration with GitHub Actions

Configure GitHub webhook to trigger MCP server actions:

**1. Start webhook receiver:**
```bash
./rpi-scripts/scripts/webhook_receiver.sh 8080 &
```

**2. Configure GitHub webhook:**
- Go to repository Settings → Webhooks
- Add webhook URL: `http://your-server:8080/webhook`
- Select events: Push, Pull Request
- Content type: `application/json`

**3. Process webhook events:**

Edit `process_webhook.sh` to add GitHub event handling:

```bash
case "$EVENT_TYPE" in
    "github_webhook")
        case "$ACTION" in
            "push")
                # Run tests on push
                ./rpi-scripts/test_mcp_local.sh
                ;;
            "opened")
                # Run security scan on PR
                ./rpi-scripts/scripts/health_check.sh
                ;;
        esac
        ;;
esac
```

---

## Testing

Run the API integration tests:

```bash
# Install bats if not already installed
# On Ubuntu/Debian:
# sudo apt-get install bats

# Run tests
cd rpi-scripts
bats tests/api_integration.bats
```

---

## Troubleshooting

### Check Logs

```bash
# View real-time logs
tail -f ./logs/parrot.log

# Search for errors
grep ERROR ./logs/parrot.log

# Search by message ID
grep "msgid:1234567890" ./logs/parrot.log
```

### Debug API Calls

```bash
# Add verbose output to curl
CURL_CMD="curl -v ..."

# Test webhook locally
nc -l -p 8080  # Listen on port
# In another terminal:
curl -X POST http://localhost:8080 -d '{"test":"data"}'
```

### Validate JSON

```bash
# Check if JSON is valid
jq empty file.json

# Format JSON
jq . file.json
```

---

## Security Best Practices

1. **Never commit secrets**: Always use `.env` files (gitignored)
2. **Validate input**: Check all webhook payloads before processing
3. **Use HTTPS**: For production, always use HTTPS for webhooks
4. **Rate limiting**: Implement rate limiting for webhook endpoints
5. **Authentication**: Add authentication for webhook endpoints
6. **Audit logs**: Log all API interactions with message IDs

---

## Next Steps

- [ ] Set up production webhook receiver with proper authentication
- [ ] Implement rate limiting for API endpoints
- [ ] Add retry logic for failed API calls
- [ ] Create monitoring dashboard for API usage
- [ ] Set up alerts for API failures

---

For more information, see [API_INTEGRATIONS.md](./API_INTEGRATIONS.md)
