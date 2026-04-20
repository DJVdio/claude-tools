#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-basic"
}

@test "on-pre-tool: Edit on *.vue triggers rule-2" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Edit","tool_input":{"file_path":"src/App.vue"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<critical-rules"* ]]
  [[ "$output" == *"rule-2"* ]]
  [[ "$output" == *"keep line width"* ]]
}

@test "on-pre-tool: Edit on *.md does not match rule-2" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "on-pre-tool: silent when no ruler" {
  cd "$(mktemp -d)"
  run bash -c 'echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"x.vue\"}}" | "'"$PLUGIN_ROOT"'/hooks/on-pre-tool.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "on-pre-tool: Bash with mysql command triggers rule-3" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Bash","tool_input":{"command":"mysql -u root"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-3"* ]]
  [[ "$output" == *"db-ops skill"* ]]
}

@test "on-pre-tool: Bash with non-mysql command does not match rule-3" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
