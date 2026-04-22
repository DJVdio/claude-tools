#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-basic"
}

teardown() {
  rm -f /tmp/ruler-cache-*.json
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

@test "on-pre-tool: matches plugin rule when opt-in + tool matches" {
  export HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.claude/plugins"
  local pdir="$BATS_TEST_TMPDIR/kp"
  mkdir -p "$pdir/.claude-plugin" "$pdir/claude-rules/rules"
  cat > "$pdir/.claude-plugin/plugin.json" <<JSON
{"name":"kp","version":"0.1.0","ruler":true}
JSON
  cat > "$pdir/claude-rules/ruler.yml" <<YAML
version: 1
rules:
  - id: edit-rule
    when: {tool: Edit}
    inject: rules/edit-rule.md
YAML
  echo "EDIT_BODY" > "$pdir/claude-rules/rules/edit-rule.md"
  cat > "$HOME/.claude/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"kp@mkt":[{"installPath":"$pdir","version":"0.1.0"}]}}
JSON
  mkdir -p "$BATS_TEST_TMPDIR/proj/.claude-rules"
  cat > "$BATS_TEST_TMPDIR/proj/.claude-rules/ruler.yml" <<YAML
version: 1
load_plugin_sources: true
rules: []
YAML
  cd "$BATS_TEST_TMPDIR/proj"
  input='{"tool_name":"Edit","tool_input":{"file_path":"any.txt"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '<critical-rules'
  echo "$output" | grep -q '⚠ kp/edit-rule'
  echo "$output" | grep -q 'EDIT_BODY'
}
