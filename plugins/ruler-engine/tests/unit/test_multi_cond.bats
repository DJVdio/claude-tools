#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-multi"
}

@test "multi-cond: Edit on src/chat file matches" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Edit","tool_input":{"file_path":"src/chat/views/Session.vue"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [[ "$output" == *"rule-x"* ]]
}

@test "multi-cond: Edit on *.sql matches" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Edit","tool_input":{"file_path":"migrations/001.sql"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [[ "$output" == *"rule-x"* ]]
}

@test "multi-cond: Bash mysql matches" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Bash","tool_input":{"command":"mysql -u root"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [[ "$output" == *"rule-x"* ]]
}

@test "multi-cond: Read on *.ts does not match" {
  cd "$FIXTURE_DIR"
  input='{"tool_name":"Read","tool_input":{"file_path":"src/chat/x.ts"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ -z "$output" ]
}

@test "multi-cond: same rule not duplicated even if 2 conds match" {
  cd "$FIXTURE_DIR"
  # src/chat/foo.sql matches both cond-1 (src/chat/**) and cond-2 (**/*.sql)
  input='{"tool_name":"Edit","tool_input":{"file_path":"src/chat/foo.sql"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  count="$(echo "$output" | grep -c '⚠ rule-x')"
  [ "$count" -eq 1 ]
}
