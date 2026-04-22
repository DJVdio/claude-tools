#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
  TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "project_load_plugin_sources: default false when field absent" {
  cat > "$TMP/ruler.yml" <<YAML
version: 1
rules: []
YAML
  run project_load_plugin_sources "$TMP/ruler.yml"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "project_load_plugin_sources: true when explicitly set" {
  cat > "$TMP/ruler.yml" <<YAML
version: 1
load_plugin_sources: true
rules: []
YAML
  run project_load_plugin_sources "$TMP/ruler.yml"
  [ "$output" = "true" ]
}

@test "get_disabled_ids: reads top-level disable array" {
  cat > "$TMP/ruler.yml" <<YAML
version: 1
disable:
  - "karpathy-rules/*"
  - other/rule
rules: []
YAML
  run get_disabled_ids "$TMP/ruler.yml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'karpathy-rules/\*'
  echo "$output" | grep -q 'other/rule'
}

@test "get_disabled_ids: empty when field absent" {
  cat > "$TMP/ruler.yml" <<YAML
version: 1
rules: []
YAML
  run get_disabled_ids "$TMP/ruler.yml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "id_is_disabled: exact match" {
  run id_is_disabled "foo/bar" "foo/bar"$'\n'"baz/qux"
  [ "$status" -eq 0 ]
}

@test "id_is_disabled: glob star match" {
  run id_is_disabled "foo/anything" "foo/*"
  [ "$status" -eq 0 ]
}

@test "id_is_disabled: no match" {
  run id_is_disabled "foo/bar" "baz/*"
  [ "$status" -ne 0 ]
}
