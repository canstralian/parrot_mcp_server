#!/usr/bin/env bats

@test "MCP server handles valid message" {
  run ./cli.sh start_mcp_server
  sleep 2
  echo '{"type":"mcp_message","content":"ping"}' > /tmp/mcp_in.json
  # Simulate sending to server (replace with actual protocol if needed)
  cat /tmp/mcp_in.json > /dev/null
  run grep 'ping' ./logs/parrot.log
  [ "$status" -eq 0 ]
  [[ "$output" == *"ping"* ]]
  run ./cli.sh stop_mcp_server
}

@test "MCP server logs error on malformed message" {
  run ./cli.sh start_mcp_server
  sleep 2
  echo '{"type":"mcp_message",' > /tmp/mcp_bad.json
  cat /tmp/mcp_bad.json > /dev/null
  run grep 'error' ./logs/parrot.log
  [ "$status" -eq 0 ]
  [[ "$output" == *"error"* ]]
  run ./cli.sh stop_mcp_server
}
