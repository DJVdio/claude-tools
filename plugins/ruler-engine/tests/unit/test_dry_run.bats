#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DRY="$PLUGIN_ROOT/bin/ruler-engine-dry-run"
  FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/ruler-basic"
}

@test "dry-run: always mode prints always rules" {
  cd "$FIXTURE_DIR"
  run "$DRY" --always
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-1"* ]]
}

@test "dry-run: tool=Edit file=App.vue prints rule-2" {
  cd "$FIXTURE_DIR"
  run "$DRY" --tool=Edit --file=App.vue
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-2"* ]]
}

@test "dry-run: tool=Bash command=mysql prints rule-3" {
  cd "$FIXTURE_DIR"
  run "$DRY" --tool=Bash --command="mysql -u root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rule-3"* ]]
}
