#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

write_ruler() {
  cat > "$TMP/ruler.yml" <<YAML
version: 1
rules:
  - id: a1
    when: always
    inject: rules/a1.md
  - id: a2
    when: always
    inject: rules/a2.md
  - id: t1
    when: {tool: Edit}
    inject: rules/t1.md
YAML
}

@test "get_always_rules_ns: prefixes id when namespace given" {
  write_ruler
  run get_always_rules_ns "$TMP/ruler.yml" "pfx"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'pfx/a1\trules/a1.md'
  echo "$output" | grep -q $'pfx/a2\trules/a2.md'
}

@test "get_always_rules_ns: no prefix when namespace empty" {
  write_ruler
  run get_always_rules_ns "$TMP/ruler.yml" ""
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'a1\trules/a1.md'
  ! echo "$output" | grep -q 'pfx/'
}

@test "get_tool_rules_ns: injects namespace into rule json" {
  write_ruler
  run get_tool_rules_ns "$TMP/ruler.yml" "pfx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "pfx/t1"' >/dev/null
  echo "$output" | jq -e '.inject == "rules/t1.md"' >/dev/null
}
