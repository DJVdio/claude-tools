#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-basic"
}

teardown() {
  rm -f /tmp/ruler-cache-*.json
}

@test "on-user-prompt: injects always rule content wrapped in <critical-rules>" {
  cd "$FIXTURE_DIR"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<critical-rules>"* ]]
  [[ "$output" == *"⚠ rule-1"* ]]
  [[ "$output" == *"Rule 1: always active reminder."* ]]
  [[ "$output" == *"</critical-rules>"* ]]
}

@test "on-user-prompt: silent when no ruler.yml upstream" {
  cd "$(mktemp -d)"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "on-user-prompt: injects plugin rule when opt-in true" {
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
  - id: always-rule
    when: always
    inject: rules/always-rule.md
YAML
  echo "PLUGIN_BODY" > "$pdir/claude-rules/rules/always-rule.md"
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
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '<critical-rules>'
  echo "$output" | grep -q '</critical-rules>'
  echo "$output" | grep -q '⚠ kp/always-rule'
  echo "$output" | grep -q 'PLUGIN_BODY'
}
