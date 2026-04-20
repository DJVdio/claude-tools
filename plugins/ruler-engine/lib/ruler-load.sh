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
