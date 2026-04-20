#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$PLUGIN_ROOT/lib/ruler-load.sh"
}

@test "glob_match: single-star matches single segment" {
  run glob_match "*.vue" "App.vue"
  [ "$status" -eq 0 ]
}

@test "glob_match: single-star does NOT cross directories" {
  run glob_match "*.vue" "src/App.vue"
  [ "$status" -ne 0 ]
}

@test "glob_match: double-star matches any depth" {
  run glob_match "src/**/*.vue" "src/chat/views/App.vue"
  [ "$status" -eq 0 ]
}

@test "glob_match: double-star matches zero depth" {
  run glob_match "src/**/*.vue" "src/App.vue"
  [ "$status" -eq 0 ]
}

@test "glob_match: no match returns 1" {
  run glob_match "**/*.ts" "App.vue"
  [ "$status" -ne 0 ]
}
