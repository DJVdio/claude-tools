#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
  FIXTURE="$PLUGIN_ROOT/tests/fixtures/ruler-basic/.claude-rules/ruler.yml"
}

@test "get_always_rules: returns only rules with when=always" {
  run get_always_rules "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$output" = "rule-1	rules/rule-1.md" ]
}

@test "get_always_rules: empty when no always rules" {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<'YAML'
version: 1
rules:
  - id: r1
    when: {tool: Edit, file_glob: "*.vue"}
    inject: rules/x.md
YAML
  run get_always_rules "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$tmp"
}
