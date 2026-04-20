#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LINT="$PLUGIN_ROOT/bin/ruler-engine-lint"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "lint: passes on valid ruler" {
  cp -r "$PLUGIN_ROOT/tests/fixtures/ruler-basic/.claude-rules" "$TMP/"
  cd "$TMP"
  run "$LINT"
  [ "$status" -eq 0 ]
}

@test "lint: fails when ruler.yml missing" {
  cd "$TMP"
  run "$LINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "lint: fails when inject file missing" {
  mkdir -p "$TMP/.claude-rules"
  cat >"$TMP/.claude-rules/ruler.yml" <<'YAML'
version: 1
rules:
  - id: rule-1
    when: always
    inject: rules/nonexistent.md
YAML
  cd "$TMP"
  run "$LINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nonexistent.md"* ]]
}

@test "lint: fails when always rules exceed 5" {
  mkdir -p "$TMP/.claude-rules/rules"
  {
    echo "version: 1"
    echo "rules:"
    for i in 1 2 3 4 5 6; do
      echo "  - id: r$i"
      echo "    when: always"
      echo "    inject: rules/r$i.md"
      touch "$TMP/.claude-rules/rules/r$i.md"
    done
  } > "$TMP/.claude-rules/ruler.yml"
  cd "$TMP"
  run "$LINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"always"* ]]
}

@test "lint: fails on mixed when array with 'always' literal" {
  mkdir -p "$TMP/.claude-rules/rules"
  touch "$TMP/.claude-rules/rules/r.md"
  cat >"$TMP/.claude-rules/ruler.yml" <<'YAML'
version: 1
rules:
  - id: r1
    when:
      - always
      - {tool: Edit, file_glob: "*.vue"}
    inject: rules/r.md
YAML
  cd "$TMP"
  run "$LINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mix"* || "$output" == *"always"* ]]
}
