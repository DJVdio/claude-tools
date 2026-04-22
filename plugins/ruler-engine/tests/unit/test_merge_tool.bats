#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
  TMP="$(mktemp -d)"
  ORIGINAL_HOME="$HOME"
  export HOME="$TMP"
  mkdir -p "$HOME/.claude/plugins"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP"
}

write_plugin_tool() {
  local dir="$TMP/karpathy-rules"
  mkdir -p "$dir/.claude-plugin" "$dir/claude-rules/rules"
  cat > "$dir/.claude-plugin/plugin.json" <<JSON
{"name":"karpathy-rules","version":"0.1.0","ruler":true}
JSON
  cat > "$dir/claude-rules/ruler.yml" <<YAML
version: 1
rules:
  - id: edit-only
    when: {tool: Edit}
    inject: rules/edit.md
YAML
  cat > "$HOME/.claude/plugins/installed_plugins.json" <<JSON
{"version":2,"plugins":{"karpathy-rules@mkt":[{"installPath":"$dir","version":"0.1.0"}]}}
JSON
}

@test "merged_tool: namespaced plugin rules appear when opt-in true" {
  write_plugin_tool
  mkdir -p "$TMP/proj/.claude-rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
load_plugin_sources: true
rules: []
YAML
  cd "$TMP/proj"
  run load_merged_tool
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "karpathy-rules/edit-only"' >/dev/null
  echo "$output" | jq -e '.dir' >/dev/null
}

@test "merged_tool: skips plugin rules when opt-in false" {
  write_plugin_tool
  mkdir -p "$TMP/proj/.claude-rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
rules: []
YAML
  cd "$TMP/proj"
  run load_merged_tool
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
