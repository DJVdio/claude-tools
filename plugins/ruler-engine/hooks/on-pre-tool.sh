#!/usr/bin/env bash
# PreToolUse hook: inject rules matching current tool + args from all active sources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/ruler-load.sh
source "$PLUGIN_ROOT/lib/ruler-load.sh"

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // empty')"
command_arg="$(echo "$input" | jq -r '.tool_input.command // empty')"

project_ruler="$(find_ruler 2>/dev/null || true)"
if [[ -z "$project_ruler" && -z "${RULER_EXTRA_SOURCES:-}" ]]; then
  exit 0
fi

matched_ids=()
matched_paths=()

while IFS= read -r rule_json; do
  [[ -z "$rule_json" ]] && continue
  id="$(echo "$rule_json" | jq -r '.id')"
  inject="$(echo "$rule_json" | jq -r '.inject')"
  dir="$(echo "$rule_json" | jq -r '.dir')"
  conds="$(echo "$rule_json" | jq -c 'if (.when | type) == "array" then .when else [.when] end')"
  n="$(echo "$conds" | jq 'length')"
  for ((i=0; i<n; i++)); do
    cond="$(echo "$conds" | jq -c ".[$i]")"
    c_tool="$(echo "$cond" | jq -r '.tool // empty')"
    c_glob="$(echo "$cond" | jq -r '.file_glob // empty')"
    c_regex="$(echo "$cond" | jq -r '.command_regex // empty')"
    [[ "$c_tool" != "$tool_name" ]] && continue
    if [[ -n "$c_glob" ]]; then
      [[ -z "$file_path" ]] && continue
      if glob_match "$c_glob" "$file_path"; then
        matched_ids+=("$id")
        matched_paths+=("$dir/$inject")
        break
      fi
    elif [[ -n "$c_regex" ]]; then
      [[ -z "$command_arg" ]] && continue
      if echo "$command_arg" | grep -Eq "$c_regex"; then
        matched_ids+=("$id")
        matched_paths+=("$dir/$inject")
        break
      fi
    else
      matched_ids+=("$id")
      matched_paths+=("$dir/$inject")
      break
    fi
  done
done < <(load_merged_tool_cached)

[[ "${#matched_ids[@]}" -eq 0 ]] && exit 0

{
  echo "<critical-rules tool=\"$tool_name\">"
  for i in "${!matched_ids[@]}"; do
    echo "⚠ ${matched_ids[$i]}"
    if [[ -f "${matched_paths[$i]}" ]]; then
      cat "${matched_paths[$i]}"
    else
      echo "(missing: ${matched_paths[$i]})"
    fi
  done
  echo "</critical-rules>"
}
