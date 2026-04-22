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

write_plugin() {
  local name="$1"
  local dir="$TMP/$name"
  mkdir -p "$dir/.claude-plugin" "$dir/claude-rules/rules"
  cat > "$dir/.claude-plugin/plugin.json" <<JSON
{"name":"$name","version":"0.1.0","ruler":true}
JSON
  cat > "$dir/claude-rules/ruler.yml" <<YAML
version: 1
rules:
  - id: always1
    when: always
    inject: rules/always1.md
YAML
  echo "body of $name/always1" > "$dir/claude-rules/rules/always1.md"
}

write_installed_with() {
  local name="$1"
  cat > "$HOME/.claude/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "$name@mkt": [{"installPath":"$TMP/$name","version":"0.1.0"}]
  }
}
JSON
}

@test "merged_always: returns project-only when opt-in false" {
  write_plugin karpathy-rules
  write_installed_with karpathy-rules
  mkdir -p "$TMP/proj/.claude-rules/rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
rules:
  - id: pj
    when: always
    inject: rules/pj.md
YAML
  echo "proj body" > "$TMP/proj/.claude-rules/rules/pj.md"
  cd "$TMP/proj"
  run load_merged_always
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'pj\t'"$TMP/proj/.claude-rules/rules/pj.md"
  ! echo "$output" | grep -q 'karpathy-rules/'
}

@test "merged_always: merges plugin rules when opt-in true" {
  write_plugin karpathy-rules
  write_installed_with karpathy-rules
  mkdir -p "$TMP/proj/.claude-rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
load_plugin_sources: true
rules: []
YAML
  cd "$TMP/proj"
  run load_merged_always
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "karpathy-rules/always1"$'\t'"$TMP/karpathy-rules/claude-rules/rules/always1.md"
}

@test "merged_always: disable filters matching ids" {
  write_plugin karpathy-rules
  write_installed_with karpathy-rules
  mkdir -p "$TMP/proj/.claude-rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
load_plugin_sources: true
disable:
  - "karpathy-rules/*"
rules: []
YAML
  cd "$TMP/proj"
  run load_merged_always
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'karpathy-rules/'
}
