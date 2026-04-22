#!/usr/bin/env bash
# UserPromptSubmit hook: inject `when: always` rules from all active sources
# (project .claude-rules/ plus opt-in plugin sources).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/ruler-load.sh
source "$PLUGIN_ROOT/lib/ruler-load.sh"

project_ruler="$(find_ruler 2>/dev/null || true)"
if [[ -z "$project_ruler" && -z "${RULER_EXTRA_SOURCES:-}" ]]; then
  exit 0
fi

rules="$(load_merged_always_cached 2>/dev/null || true)"
[[ -z "$rules" ]] && exit 0

{
  echo "<critical-rules>"
  while IFS=$'\t' read -r id abspath; do
    [[ -z "$id" ]] && continue
    echo "⚠ $id"
    if [[ -f "$abspath" ]]; then
      cat "$abspath"
    else
      echo "(missing: $abspath)"
    fi
  done <<< "$rules"
  echo "</critical-rules>"
}
