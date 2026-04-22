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

@test "lint: catches array-form Bash with file_glob" {
  mkdir -p "$TMP/.claude-rules/rules"
  touch "$TMP/.claude-rules/rules/r.md"
  cat >"$TMP/.claude-rules/ruler.yml" <<'YAML'
version: 1
rules:
  - id: r1
    when:
      - {tool: Bash, file_glob: "*.sh"}
    inject: rules/r.md
YAML
  cd "$TMP"
  run "$LINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file_glob"* ]]
}

@test "lint: catches array-form condition missing tool" {
  mkdir -p "$TMP/.claude-rules/rules"
  touch "$TMP/.claude-rules/rules/r.md"
  cat >"$TMP/.claude-rules/ruler.yml" <<'YAML'
version: 1
rules:
  - id: r1
    when:
      - {file_glob: "*.vue"}
    inject: rules/r.md
YAML
  cd "$TMP"
  run "$LINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tool required"* ]]
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

@test "lint: --file <path> mode works outside project" {
  mkdir -p "$TMP/rules"
  touch "$TMP/rules/r.md"
  cat > "$TMP/any.yml" <<YAML
version: 1
rules:
  - id: r1
    when: always
    inject: rules/r.md
YAML
  cd /tmp
  run "$PLUGIN_ROOT/bin/ruler-engine-lint" --file="$TMP/any.yml"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'OK'
}

@test "lint: invalid load_plugin_sources type errors" {
  mkdir -p "$TMP/.claude-rules"
  cat > "$TMP/.claude-rules/ruler.yml" <<YAML
version: 1
load_plugin_sources: "yes"
rules:
  - id: r1
    when: always
    inject: /dev/null
YAML
  cd "$TMP"
  run "$PLUGIN_ROOT/bin/ruler-engine-lint"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'load_plugin_sources'
}

@test "lint: disable must be array of strings" {
  mkdir -p "$TMP/.claude-rules"
  cat > "$TMP/.claude-rules/ruler.yml" <<YAML
version: 1
disable: "just-a-string"
rules:
  - id: r1
    when: always
    inject: /dev/null
YAML
  cd "$TMP"
  run "$PLUGIN_ROOT/bin/ruler-engine-lint"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'disable'
}

@test "lint: warns on aggregate always-rules >2KB" {
  mkdir -p "$TMP/.claude-rules/rules"
  cat > "$TMP/.claude-rules/ruler.yml" <<YAML
version: 1
rules:
  - id: big
    when: always
    inject: rules/big.md
YAML
  python3 -c "print('x'*2500, end='')" > "$TMP/.claude-rules/rules/big.md"
  cd "$TMP"
  run "$PLUGIN_ROOT/bin/ruler-engine-lint"
  [ "$status" -eq 0 ]
  # Warning goes to stderr; merge stderr into combined output for grep
  run bash -c "'$PLUGIN_ROOT/bin/ruler-engine-lint' 2>&1"
  echo "$output" | grep -q 'aggregate'
}

@test "lint: warns on dangling disable id" {
  mkdir -p "$TMP/.claude-rules"
  touch "$TMP/.claude-rules/r1.md"
  cat > "$TMP/.claude-rules/ruler.yml" <<YAML
version: 1
disable:
  - "nonexistent/thing"
rules:
  - id: r1
    when: always
    inject: r1.md
YAML
  cd "$TMP"
  run bash -c "'$PLUGIN_ROOT/bin/ruler-engine-lint' 2>&1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'dangling\|no rule matches'
}
