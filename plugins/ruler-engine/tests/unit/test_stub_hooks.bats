#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
}

@test "on-user-prompt.sh exits 0 when no .claude-rules/ found" {
  cd "$(mktemp -d)"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "on-pre-tool.sh exits 0 when no .claude-rules/ found" {
  cd "$(mktemp -d)"
  run bash -c 'echo "{\"tool_name\":\"Edit\"}" | "'"$PLUGIN_ROOT"'/hooks/on-pre-tool.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
