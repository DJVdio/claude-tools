#!/usr/bin/env bash
# PreToolUse hook: inject rules matching current tool + args
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/ruler-load.sh
source "$PLUGIN_ROOT/lib/ruler-load.sh"

# Read stdin JSON
input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // empty')"
command_arg="$(echo "$input" | jq -r '.tool_input.command // empty')"

ruler_file="$(find_ruler)" || exit 0
ruler_dir="$(dirname "$ruler_file")"

# Iterate non-always rules; emit matched ones
matched_ids=()
matched_paths=()

while IFS= read -r rule_json; do
  [[ -z "$rule_json" ]] && continue
  id="$(echo "$rule_json" | jq -r '.id')"
  inject="$(echo "$rule_json" | jq -r '.inject')"
  # `when` can be object or array
  # Normalize to array
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
        matched_paths+=("$inject")
        break
      fi
    elif [[ -n "$c_regex" ]]; then
      [[ -z "$command_arg" ]] && continue
      if echo "$command_arg" | grep -Eq "$c_regex"; then
        matched_ids+=("$id")
        matched_paths+=("$inject")
        break
      fi
    else
      # tool-only match
      matched_ids+=("$id")
      matched_paths+=("$inject")
      break
    fi
  done
done < <(get_tool_rules "$ruler_file")

[[ "${#matched_ids[@]}" -eq 0 ]] && exit 0

# Emit injection
{
  ids_csv="$(IFS=,; echo "${matched_ids[*]}")"
  echo "<ruler-reminder tool=\"$tool_name\" match=\"$ids_csv\">"
  echo "Claude 即将调用 $tool_name 工具，以下规则适用："
  echo ""
  for i in "${!matched_ids[@]}"; do
    echo "=== ${matched_ids[$i]} (from ${matched_paths[$i]}) ==="
    if [[ -f "$ruler_dir/${matched_paths[$i]}" ]]; then
      cat "$ruler_dir/${matched_paths[$i]}"
    else
      echo "(missing file: ${matched_paths[$i]})"
    fi
    echo ""
  done
  echo "</ruler-reminder>"
}
