#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PLUGIN_ROOT
  PROJ="$(mktemp -d)"
  mkdir -p "$PROJ/.claude-rules/rules" "$PROJ/src/chat"

  cat >"$PROJ/.claude-rules/ruler.yml" <<'YAML'
version: 1
rules:
  - id: overview
    when: always
    inject: rules/overview.md
  - id: chat
    when: {tool: Edit, file_glob: "src/chat/**"}
    inject: rules/chat.md
YAML

  echo "Project overview reminder." > "$PROJ/.claude-rules/rules/overview.md"
  echo "Chat module rules: preserve composables." > "$PROJ/.claude-rules/rules/chat.md"
}

teardown() {
  rm -rf "$PROJ"
}

@test "integration: lint passes on realistic project" {
  cd "$PROJ"
  run "$PLUGIN_ROOT/bin/ruler-engine-lint"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "integration: UserPromptSubmit injects overview" {
  cd "$PROJ"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project overview reminder."* ]]
}

@test "integration: PreToolUse Edit on src/chat/x.vue injects chat rule" {
  cd "$PROJ"
  input='{"tool_name":"Edit","tool_input":{"file_path":"src/chat/views/Session.vue"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"preserve composables"* ]]
}

@test "integration: PreToolUse Edit on non-chat file does not inject chat" {
  cd "$PROJ"
  input='{"tool_name":"Edit","tool_input":{"file_path":"src/util/x.ts"}}'
  run bash -c "echo '$input' | '$PLUGIN_ROOT/hooks/on-pre-tool.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"preserve composables"* ]]
}

@test "integration: deep nested cwd still finds ruler" {
  mkdir -p "$PROJ/src/chat/deep/nested/path"
  cd "$PROJ/src/chat/deep/nested/path"
  run "$PLUGIN_ROOT/hooks/on-user-prompt.sh"
  [[ "$output" == *"Project overview reminder."* ]]
}

@test "integration: hook respects 1s timeout boundary (completes <1s on small ruler)" {
  cd "$PROJ"
  start="$(python3 -c 'import time; print(int(time.time()*1000))')"
  "$PLUGIN_ROOT/hooks/on-user-prompt.sh" >/dev/null
  end="$(python3 -c 'import time; print(int(time.time()*1000))')"
  elapsed_ms=$(( end - start ))
  [ "$elapsed_ms" -lt 1000 ]
}

@test "integration: dry-run reproduces PreToolUse output" {
  cd "$PROJ"
  run "$PLUGIN_ROOT/bin/ruler-engine-dry-run" --tool=Edit --file=src/chat/x.vue
  [[ "$output" == *"preserve composables"* ]]
}
