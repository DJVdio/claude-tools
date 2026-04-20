#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "find_ruler: returns path when ruler.yml exists in cwd" {
  mkdir -p "$TMP/.claude-rules"
  touch "$TMP/.claude-rules/ruler.yml"
  cd "$TMP"
  run find_ruler
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/.claude-rules/ruler.yml" ]
}

@test "find_ruler: walks up directories" {
  mkdir -p "$TMP/.claude-rules" "$TMP/a/b/c"
  touch "$TMP/.claude-rules/ruler.yml"
  cd "$TMP/a/b/c"
  run find_ruler
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/.claude-rules/ruler.yml" ]
}

@test "find_ruler: returns nonzero when not found" {
  cd "$TMP"
  run find_ruler
  [ "$status" -ne 0 ]
}
