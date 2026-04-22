#!/usr/bin/env bash
# Ruler loading primitives. Source this from hook scripts.

# find_ruler [dir]
#   Walk upwards from $dir (default $PWD), return path to .claude-rules/ruler.yml
#   if found. Returns 1 if not found.
find_ruler() {
  local dir="${1:-$PWD}"
  dir="$(cd "$dir" && pwd)"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/.claude-rules/ruler.yml" ]]; then
      echo "$dir/.claude-rules/ruler.yml"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# get_always_rules <ruler_file>
#   Print tab-separated "<id>\t<inject_path>" for each rule with when=always.
get_always_rules() {
  local file="$1"
  yq eval '.rules[] | select(.when == "always") | .id + "\t" + .inject' "$file" 2>/dev/null
}

# glob_match <glob> <path>
#   Returns 0 if path matches glob. Supports ** for any-depth matching,
#   * for single-segment, ? for single char, [] for char classes.
glob_match() {
  local glob="$1" path="$2"
  python3 - "$path" "$glob" <<'PY'
import re, sys
path, glob = sys.argv[1], sys.argv[2]

def translate(g):
    i, n = 0, len(g)
    out = ['^']
    while i < n:
        c = g[i]
        if c == '*':
            if i+1 < n and g[i+1] == '*':
                # Consume any trailing slash for ** to allow zero depth
                j = i + 2
                if j < n and g[j] == '/':
                    out.append('(?:.*/)?')
                    i = j + 1
                    continue
                out.append('.*')
                i += 2
            else:
                out.append('[^/]*')
                i += 1
        elif c == '?':
            out.append('[^/]')
            i += 1
        elif c == '[':
            j = g.find(']', i+1)
            if j == -1:
                out.append(re.escape(c))
                i += 1
            else:
                out.append(g[i:j+1])
                i = j + 1
        else:
            out.append(re.escape(c))
            i += 1
    out.append('$')
    return ''.join(out)

pat = translate(glob)
sys.exit(0 if re.match(pat, path) else 1)
PY
}

# get_tool_rules <ruler_file>
#   Print JSON array of non-always rules, one rule per line.
get_tool_rules() {
  local file="$1"
  yq eval -o=json -I=0 '.rules[] | select(.when != "always")' "$file" 2>/dev/null || true
}

# get_installed_plugins
#   Emit tab-separated "<plugin_name>\t<install_path>" for each installed plugin.
#   Plugin name = map key before the first "@" (strips the @marketplace suffix).
#   Returns 0 with empty output when installed_plugins.json is missing.
get_installed_plugins() {
  local f="$HOME/.claude/plugins/installed_plugins.json"
  [[ -f "$f" ]] || return 0
  jq -r '
    .plugins // {} | to_entries[]
    | .key as $k
    | (.value[0].installPath // "") as $p
    | select($p != "")
    | ($k | split("@")[0]) + "\t" + $p
  ' "$f" 2>/dev/null || true
}

# find_plugin_sources
#   Emit tab-separated "<namespace>\t<ruler_yml_path>" for each installed plugin
#   whose plugin.json has "ruler": true AND has claude-rules/ruler.yml on disk.
#   Also honors $RULER_EXTRA_SOURCES (comma-separated "ns:path" pairs).
find_plugin_sources() {
  while IFS=$'\t' read -r name path; do
    [[ -z "$name" || -z "$path" ]] && continue
    local manifest="$path/.claude-plugin/plugin.json"
    local ruler="$path/claude-rules/ruler.yml"
    [[ ! -f "$manifest" || ! -f "$ruler" ]] && continue
    local flag
    flag="$(jq -r '.ruler // false' "$manifest" 2>/dev/null)"
    [[ "$flag" == "true" ]] || continue
    printf '%s\t%s\n' "$name" "$ruler"
  done < <(get_installed_plugins)

  # Env-var injected sources (dev escape hatch)
  if [[ -n "${RULER_EXTRA_SOURCES:-}" ]]; then
    local IFS_OLD="$IFS"
    IFS=','
    for entry in $RULER_EXTRA_SOURCES; do
      IFS="$IFS_OLD"
      local ns="${entry%%:*}"
      local path="${entry#*:}"
      [[ -z "$ns" || -z "$path" || ! -f "$path" ]] && continue
      printf '%s\t%s\n' "$ns" "$path"
    done
    IFS="$IFS_OLD"
  fi
}
