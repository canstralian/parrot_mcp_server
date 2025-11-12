#!/usr/bin/env bats

@test "MCP server handles valid message" {
  # Clean up from previous tests
  rm -f /tmp/mcp_in.json /tmp/mcp_bad.json
  ./rpi-scripts/stop_mcp_server.sh 2>/dev/null || true

  # Start server
  run ./rpi-scripts/start_mcp_server.sh
  sleep 2

  # Send valid message
  echo '{"type":"mcp_message","content":"ping"}' > /tmp/mcp_in.json

  # Wait for processing
  sleep 1

  # Check logs for ping message
  run grep 'ping' ./logs/parrot.log
  [ "$status" -eq 0 ]
  [[ "$output" == *"ping"* ]]

  # Clean up
  ./rpi-scripts/stop_mcp_server.sh
  rm -f /tmp/mcp_in.json
}

@test "MCP server logs error on malformed message" {
  # Clean up from previous tests
  rm -f /tmp/mcp_in.json /tmp/mcp_bad.json
  ./rpi-scripts/stop_mcp_server.sh 2>/dev/null || true

  # Start server
  run ./rpi-scripts/start_mcp_server.sh
  sleep 2

  # Send malformed message
  echo '{"type":"mcp_message",' > /tmp/mcp_bad.json

  # Wait for processing
  sleep 1

  # Check logs for error (case-insensitive)
  run grep -i 'error' ./logs/parrot.log
  [ "$status" -eq 0 ]
  [[ "$output" =~ [Ee][Rr][Rr][Oo][Rr] ]]

  # Clean up
  ./rpi-scripts/stop_mcp_server.sh
  rm -f /tmp/mcp_bad.json
}
