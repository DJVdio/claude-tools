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
