#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DRY="$PLUGIN_ROOT/bin/ruler-engine-dry-run"
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-basic"
  TMP="$(mktemp -d)"
  ORIGINAL_HOME="$HOME"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP"
}

@test "dry-run: always mode prints always rules" {
  cd "$FIXTURE_DIR"
  run "$DRY" --always
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-1"* ]]
}

@test "dry-run: tool=Edit file=App.vue prints rule-2" {
  cd "$FIXTURE_DIR"
  run "$DRY" --tool=Edit --file=App.vue
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-2"* ]]
}

@test "dry-run: tool=Bash command=mysql prints rule-3" {
  cd "$FIXTURE_DIR"
  run "$DRY" --tool=Bash --command="mysql -u root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-3"* ]]
}

@test "dry-run --sources: lists project + plugin sources" {
  export HOME="$TMP"
  mkdir -p "$HOME/.claude/plugins"
  local pdir="$TMP/kp"
  mkdir -p "$pdir/.claude-plugin" "$pdir/claude-rules"
  cat > "$pdir/.claude-plugin/plugin.json" <<JSON
{"name":"kp","version":"0.1.0","ruler":true}
JSON
  echo 'version: 1' > "$pdir/claude-rules/ruler.yml"
  echo 'rules: []' >> "$pdir/claude-rules/ruler.yml"
  cat > "$HOME/.claude/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"kp@mkt":[{"installPath":"$pdir","version":"0.1.0"}]}}
JSON
  mkdir -p "$TMP/proj/.claude-rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
load_plugin_sources: true
rules: []
YAML
  cd "$TMP/proj"
  run "$PLUGIN_ROOT/bin/ruler-engine-dry-run" --sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'kp'
  echo "$output" | grep -q "$TMP/proj/.claude-rules/ruler.yml"
}
