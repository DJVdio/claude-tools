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

write_installed() {
  cat > "$HOME/.claude/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "foo@mkt": [{"scope":"user","installPath":"$TMP/foo","version":"0.1.0"}],
    "bar@mkt": [{"scope":"user","installPath":"$TMP/bar","version":"0.2.0"}]
  }
}
JSON
}

@test "get_installed_plugins: emits name\tinstallPath lines" {
  write_installed
  run get_installed_plugins
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'foo\t'"$TMP/foo"
  echo "$output" | grep -q $'bar\t'"$TMP/bar"
}

@test "get_installed_plugins: empty when file absent" {
  run get_installed_plugins
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

setup_mock_plugin() {
  local name="$1" has_flag="$2" has_rules="$3"
  local dir="$TMP/$name"
  mkdir -p "$dir/.claude-plugin"
  if [[ "$has_flag" == "1" ]]; then
    cat > "$dir/.claude-plugin/plugin.json" <<JSON
{"name":"$name","version":"0.1.0","ruler":true}
JSON
  else
    cat > "$dir/.claude-plugin/plugin.json" <<JSON
{"name":"$name","version":"0.1.0"}
JSON
  fi
  if [[ "$has_rules" == "1" ]]; then
    mkdir -p "$dir/claude-rules"
    touch "$dir/claude-rules/ruler.yml"
  fi
}

@test "find_plugin_sources: includes only flagged plugins with ruler.yml" {
  write_installed
  setup_mock_plugin foo 1 1
  setup_mock_plugin bar 0 1   # has rules dir but no flag
  run find_plugin_sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'foo\t'"$TMP/foo/claude-rules/ruler.yml"
  ! echo "$output" | grep -q $'bar\t'
}

@test "find_plugin_sources: skips plugin missing ruler.yml file" {
  write_installed
  setup_mock_plugin foo 1 0
  setup_mock_plugin bar 1 1
  run find_plugin_sources
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q $'foo\t'
  echo "$output" | grep -q $'bar\t'
}

@test "find_plugin_sources: honors RULER_EXTRA_SOURCES env var" {
  mkdir -p "$TMP/extra"
  touch "$TMP/extra/ruler.yml"
  export RULER_EXTRA_SOURCES="dev-extras:$TMP/extra/ruler.yml"
  run find_plugin_sources
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'dev-extras\t'"$TMP/extra/ruler.yml"
}
