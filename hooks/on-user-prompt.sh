#!/usr/bin/env bash
# UserPromptSubmit hook: inject `when: always` rules from .claude-rules/ruler.yml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/ruler-load.sh
source "$PLUGIN_ROOT/lib/ruler-load.sh"

ruler_file="$(find_ruler)" || exit 0
ruler_dir="$(dirname "$ruler_file")"

# Collect always rules (id\tinject_path lines)
always_rules="$(get_always_rules "$ruler_file")"
[[ -z "$always_rules" ]] && exit 0

# Build injection
{
  echo "<ruler-reminder>"
  echo "以下是 .claude-rules/ 中声明的常驻规则，请始终遵守："
  echo ""
  while IFS=$'\t' read -r id inject; do
    [[ -z "$id" ]] && continue
    echo "=== $id (from $inject) ==="
    if [[ -f "$ruler_dir/$inject" ]]; then
      cat "$ruler_dir/$inject"
    else
      echo "(missing file: $inject)"
    fi
    echo ""
  done <<< "$always_rules"
  echo "</ruler-reminder>"
}
