#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
  TMP="$(mktemp -d)"
  ORIGINAL_HOME="$HOME"
  export HOME="$TMP"
  mkdir -p "$HOME/.claude/plugins"
  mkdir -p "$TMP/proj/.claude-rules/rules"
  cat > "$TMP/proj/.claude-rules/ruler.yml" <<YAML
version: 1
rules:
  - id: x
    when: always
    inject: rules/x.md
YAML
  echo "x body" > "$TMP/proj/.claude-rules/rules/x.md"
  cd "$TMP/proj"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TMP"
  ruler_cache_clear 2>/dev/null || true
}

@test "cache_key: stable across calls when no files change" {
  k1="$(ruler_cache_key)"
  k2="$(ruler_cache_key)"
  [ "$k1" = "$k2" ]
  [ -n "$k1" ]
}

@test "cache_key: changes when project ruler mtime changes" {
  k1="$(ruler_cache_key)"
  sleep 1
  touch "$TMP/proj/.claude-rules/ruler.yml"
  k2="$(ruler_cache_key)"
  [ "$k1" != "$k2" ]
}

@test "load_merged_always_cached: first miss then hit" {
  ruler_cache_clear
  run load_merged_always_cached
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'x\t'
  # Second call reads from cache — verify by checking file exists
  run load_merged_always_cached
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'x\t'
  ls /tmp/ruler-cache-*.json | head -1 | grep -q 'ruler-cache'
}
