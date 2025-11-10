# API Integrations for Parrot MCP Server

This document outlines API integration patterns and capabilities for the Parrot MCP Server, enabling communication with external services while maintaining the project's lightweight, shell-based philosophy.

---

## Overview

The Parrot MCP Server supports several API integration patterns that allow it to:
- Receive requests from external services (webhooks, HTTP endpoints)
- Make requests to external APIs (REST, JSON-RPC)
- Integrate with AI/LLM services
- Connect to monitoring and logging systems

---

## Integration Patterns

### 1. Incoming Webhooks

Receive events from external services like GitHub, GitLab, or monitoring systems.

**Use Cases:**
- Trigger MCP workflows from CI/CD pipelines
- Respond to security alerts from monitoring systems
- Process GitHub webhook events for automated responses

**Implementation:** Use lightweight HTTP listeners (netcat, socat, or minimal HTTP servers)

**Example:**
```bash
# Simple webhook receiver using netcat
while true; do
  echo -e "HTTP/1.1 200 OK\n\n" | nc -l -p 8080 -q 1 > webhook_payload.json
  # Process webhook payload
  ./rpi-scripts/scripts/process_webhook.sh webhook_payload.json
done
```

### 2. Outgoing REST API Calls

Make HTTP requests to external APIs for data retrieval or action execution.

**Use Cases:**
- Query vulnerability databases
- Send notifications to Slack/Discord
- Integrate with ticketing systems (Jira, GitHub Issues)
- Pull data from external services

**Implementation:** Use `curl` or `wget` for HTTP requests

**Example:**
```bash
# Query an external API
curl -X POST https://api.example.com/scan \
  -H "Content-Type: application/json" \
  -d '{"target": "192.168.1.1", "type": "port-scan"}' \
  | jq '.results'
```

### 3. MCP JSON-RPC Protocol

Implement the Model Context Protocol's JSON-RPC 2.0 message format for standard AI agent communication.

**Message Format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "nmap_scan",
    "arguments": {
      "target": "192.168.1.0/24",
      "ports": "1-1000"
    }
  }
}
```

**Response Format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Scan completed. 3 hosts found with 12 open ports."
      }
    ]
  }
}
```

### 4. AI/LLM Service Integration

Connect to AI services like OpenAI, Anthropic Claude, or Google Gemini for enhanced automation.

**Use Cases:**
- Analyze security scan results with AI
- Generate reports automatically
- Natural language command interpretation
- Automated threat assessment

**Implementation:** Use service-specific CLI tools or curl with API keys

**Example:**
```bash
# Query OpenAI API (requires API key)
OPENAI_API_KEY="your-key-here"
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Analyze this nmap output..."}]
  }'
```

---

## Security Considerations

### Authentication
- Always use environment variables for API keys and secrets
- Never commit credentials to the repository
- Use `.env` files (gitignored) for local development
- Consider using secret management tools (HashiCorp Vault, AWS Secrets Manager)

### Input Validation
- Sanitize all external inputs to prevent command injection
- Validate JSON payloads before processing
- Use whitelists for allowed commands and parameters

### Rate Limiting
- Implement rate limiting for incoming webhook requests
- Respect API rate limits for outgoing requests
- Use exponential backoff for retries

### Logging
- Log all API interactions to `./logs/parrot.log`
- Include timestamps, message IDs, and correlation IDs
- Sanitize sensitive data before logging

---

## Example Integrations

### GitHub Webhook Integration

```bash
#!/usr/bin/env bash
# scripts/github_webhook_handler.sh
# Handles GitHub webhook events

PAYLOAD="$1"
EVENT_TYPE=$(jq -r '.action' "$PAYLOAD")

case "$EVENT_TYPE" in
  "opened")
    echo "New PR opened, triggering security scan..."
    ./scripts/security_scan.sh
    ;;
  "push")
    echo "New push detected, running health checks..."
    ./scripts/health_check.sh
    ;;
  *)
    echo "Unhandled event: $EVENT_TYPE"
    ;;
esac
```

### Slack Notification Integration

```bash
#!/usr/bin/env bash
# scripts/notify_slack.sh
# Send notifications to Slack

WEBHOOK_URL="${SLACK_WEBHOOK_URL}"
MESSAGE="$1"

curl -X POST "$WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d "{\"text\":\"$MESSAGE\"}"
```

### Vulnerability Database Query

```bash
#!/usr/bin/env bash
# scripts/query_nvd.sh
# Query NIST National Vulnerability Database

CVE_ID="$1"
API_KEY="${NVD_API_KEY}"

curl "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=${CVE_ID}" \
  -H "apiKey: ${API_KEY}" \
  | jq '.vulnerabilities[0].cve.descriptions'
```

---

## Configuration

### Environment Variables

Create a `.env` file for API credentials (add to `.gitignore`):

```bash
# .env
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
OPENAI_API_KEY=sk-...
GITHUB_TOKEN=ghp_...
NVD_API_KEY=...
```

Load environment variables in scripts:

```bash
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi
```

---

## Testing API Integrations

### Mock API Responses

Use local mock servers for testing:

```bash
# Start a simple mock API server
python3 -m http.server 8000 &
echo '{"status": "ok"}' > index.html
```

### Test Webhook Handling

```bash
# Send test webhook payload
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d @test_webhook_payload.json
```

### Verify API Calls

```bash
# Test external API call with dry-run
SLACK_WEBHOOK_URL="http://localhost:8000/test" \
  ./scripts/notify_slack.sh "Test message"
```

---

## Future Enhancements

- [ ] WebSocket support for real-time communication
- [ ] GraphQL API integration
- [ ] OAuth 2.0 authentication flow
- [ ] API request caching and retry logic
- [ ] Prometheus metrics endpoint
- [ ] OpenAPI/Swagger specification generation
- [ ] Rate limiting middleware
- [ ] Circuit breaker pattern for external API calls

---

## References

- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [GitHub Webhooks Documentation](https://docs.github.com/en/webhooks)
- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [Slack API Documentation](https://api.slack.com/)

---

For questions or contributions, please open an issue or submit a PR.
