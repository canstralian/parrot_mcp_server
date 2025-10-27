#!/usr/bin/env bats

@test "hello script outputs greeting" {
  run ./cli.sh hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello from Raspberry Pi 5"* ]]
}
