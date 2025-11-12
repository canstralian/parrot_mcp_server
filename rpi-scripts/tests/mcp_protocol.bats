#!/usr/bin/env bats

# Get log file path from common_config
setup() {
    cd "$(dirname "$BATS_TEST_FILENAME")/.."
    # shellcheck source=../common_config.sh disable=SC1091
    source ./common_config.sh
}

@test "MCP server handles valid message" {
  # Clean up first
  rm -f /tmp/mcp_*.json
  
  # Start server and send message
  echo '{"type":"mcp_message","content":"ping"}' > /tmp/mcp_in.json
  ./start_mcp_server.sh
  sleep 6
  
  # Check log
  run grep 'ping' "$PARROT_SERVER_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ping"* ]]
  
  # Stop server
  ./stop_mcp_server.sh
}

@test "MCP server logs error on malformed message" {
  # Clean up first
  rm -f /tmp/mcp_*.json
  
  # Start server with bad message
  echo '{"type":"mcp_message",' > /tmp/mcp_bad.json
  ./start_mcp_server.sh
  sleep 6
  
  # Check error log (case-insensitive)
  run grep -i 'error\|malformed' "$PARROT_SERVER_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"Malformed"* ]]
  
  # Stop server
  ./stop_mcp_server.sh
}
