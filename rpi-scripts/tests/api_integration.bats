#!/usr/bin/env bats

# API Integration Tests

setup() {
    # Create test directory and logs
    mkdir -p ./logs
    mkdir -p /tmp/test_api
    export TEST_LOG="./logs/parrot.log"
}

teardown() {
    # Cleanup test files
    rm -f /tmp/test_api/*.json
}

@test "process_webhook handles valid MCP message" {
    # Create test webhook payload
    echo '{"type":"mcp_message","method":"ping","id":1}' > /tmp/test_api/test_webhook.json
    
    # Process webhook
    run bash ./scripts/process_webhook.sh /tmp/test_api/test_webhook.json
    
    [ "$status" -eq 0 ]
    
    # Check logs
    run grep "MCP message received via webhook" "$TEST_LOG"
    [ "$status" -eq 0 ]
}

@test "process_webhook handles GitHub webhook" {
    # Create test GitHub webhook payload
    echo '{"type":"github_webhook","action":"push","repository":"test/repo"}' > /tmp/test_api/github_webhook.json
    
    # Process webhook
    run bash ./scripts/process_webhook.sh /tmp/test_api/github_webhook.json
    
    [ "$status" -eq 0 ]
    
    # Check logs
    run grep "GitHub webhook" "$TEST_LOG"
    [ "$status" -eq 0 ]
}

@test "process_webhook rejects invalid JSON" {
    # Create invalid JSON payload
    echo '{"type":"mcp_message",' > /tmp/test_api/invalid.json
    
    # Process webhook (should fail)
    run bash ./scripts/process_webhook.sh /tmp/test_api/invalid.json
    
    [ "$status" -eq 1 ]
    
    # Check error in logs
    run grep "Invalid JSON" "$TEST_LOG"
    [ "$status" -eq 0 ]
}

@test "mcp_jsonrpc handles ping request" {
    # Create JSON-RPC ping request
    echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' > /tmp/test_api/ping_request.json
    
    # Process request
    run bash ./scripts/mcp_jsonrpc.sh /tmp/test_api/ping_request.json /tmp/test_api/ping_response.json
    
    [ "$status" -eq 0 ]
    [ -f /tmp/test_api/ping_response.json ]
    
    # Check response contains "pong"
    run grep "pong" /tmp/test_api/ping_response.json
    [ "$status" -eq 0 ]
}

@test "mcp_jsonrpc handles tools/call request" {
    # Create JSON-RPC tools/call request
    echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"health_check"}}' > /tmp/test_api/tool_request.json
    
    # Process request
    run bash ./scripts/mcp_jsonrpc.sh /tmp/test_api/tool_request.json /tmp/test_api/tool_response.json
    
    [ "$status" -eq 0 ]
    [ -f /tmp/test_api/tool_response.json ]
    
    # Check response is valid JSON
    run jq empty /tmp/test_api/tool_response.json
    [ "$status" -eq 0 ]
}

@test "mcp_jsonrpc returns error for unknown method" {
    # Create request with unknown method
    echo '{"jsonrpc":"2.0","id":3,"method":"unknown_method"}' > /tmp/test_api/unknown_request.json
    
    # Process request (should return error)
    run bash ./scripts/mcp_jsonrpc.sh /tmp/test_api/unknown_request.json /tmp/test_api/unknown_response.json
    
    [ "$status" -eq 1 ]
    [ -f /tmp/test_api/unknown_response.json ]
    
    # Check error response
    run jq -r '.error.code' /tmp/test_api/unknown_response.json
    [ "$output" = "-32601" ]
}

@test "mcp_jsonrpc validates JSON-RPC version" {
    # Create request with wrong version
    echo '{"jsonrpc":"1.0","id":4,"method":"ping"}' > /tmp/test_api/wrong_version.json
    
    # Process request (should return error)
    run bash ./scripts/mcp_jsonrpc.sh /tmp/test_api/wrong_version.json /tmp/test_api/version_response.json
    
    [ "$status" -eq 1 ]
    
    # Check error response
    run jq -r '.error.code' /tmp/test_api/version_response.json
    [ "$output" = "-32600" ]
}

@test "api_client can make GET request" {
    skip "Requires network access"
    
    # Test GET request to httpbin
    run bash ./scripts/api_client.sh GET "https://httpbin.org/get"
    
    [ "$status" -eq 0 ]
}

@test "notify_slack fails without SLACK_WEBHOOK_URL" {
    # Unset SLACK_WEBHOOK_URL
    unset SLACK_WEBHOOK_URL
    
    # Try to send notification (should fail)
    run bash ./scripts/notify_slack.sh "Test message"
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"SLACK_WEBHOOK_URL not set"* ]]
}
