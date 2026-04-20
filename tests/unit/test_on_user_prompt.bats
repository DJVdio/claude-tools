#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-basic"
}

@test "on-user-prompt: injects always rule content wrapped in <ruler-reminder>" {
  cd "$FIXTURE_DIR"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<ruler-reminder>"* ]]
  [[ "$output" == *"=== rule-1"* ]]
  [[ "$output" == *"Rule 1: always active reminder."* ]]
  [[ "$output" == *"</ruler-reminder>"* ]]
}

@test "on-user-prompt: silent when no ruler.yml upstream" {
  cd "$(mktemp -d)"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
