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

# get_always_rules_ns <ruler_file> <namespace>
#   Like get_always_rules but prefixes id with "<namespace>/" when namespace
#   is non-empty. Preserves "<prefixed_id>\t<inject>" format.
get_always_rules_ns() {
  local file="$1" ns="$2"
  local raw
  raw="$(get_always_rules "$file")"
  [[ -z "$ns" ]] && { printf '%s\n' "$raw"; return 0; }
  while IFS=$'\t' read -r id inject; do
    [[ -z "$id" ]] && continue
    printf '%s/%s\t%s\n' "$ns" "$id" "$inject"
  done <<< "$raw"
}

# get_tool_rules_ns <ruler_file> <namespace>
#   Like get_tool_rules but rewrites .id to "<namespace>/<id>" when namespace
#   is non-empty. Output remains JSONL (one rule per line).
get_tool_rules_ns() {
  local file="$1" ns="$2"
  if [[ -z "$ns" ]]; then
    get_tool_rules "$file"
    return 0
  fi
  get_tool_rules "$file" | jq -c --arg ns "$ns" '.id = ($ns + "/" + .id)'
}

# project_load_plugin_sources <ruler_file>
#   Echo "true" or "false" based on top-level load_plugin_sources field.
project_load_plugin_sources() {
  local file="$1"
  [[ -f "$file" ]] || { echo "false"; return 0; }
  local v
  v="$(yq eval '.load_plugin_sources // false' "$file" 2>/dev/null)"
  [[ "$v" == "true" ]] && echo "true" || echo "false"
}

# get_disabled_ids <ruler_file>
#   Emit one id-or-glob per line from top-level disable[] array.
get_disabled_ids() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  yq eval '.disable // [] | .[]' "$file" 2>/dev/null | grep -v '^$' || true
}

# id_is_disabled <id> <disable_list_multi_line>
#   Returns 0 if id matches any glob pattern in the newline-separated list.
id_is_disabled() {
  local id="$1" list="$2"
  [[ -z "$list" ]] && return 1
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    # Use bash extglob-free fnmatch via case pattern
    case "$id" in
      $pat) return 0 ;;
    esac
  done <<< "$list"
  return 1
}

# load_merged_always
#   Emit "<id>\t<absolute_inject_path>" lines for every always-rule that
#   should be injected, respecting opt-in gate and disable list.
#   Absolute paths let hook consumers cat files without re-tracking dirs.
load_merged_always() {
  local project_ruler
  project_ruler="$(find_ruler 2>/dev/null || true)"

  local disable_list=""
  [[ -n "$project_ruler" ]] && disable_list="$(get_disabled_ids "$project_ruler")"

  local opt_in="false"
  [[ -n "$project_ruler" ]] && opt_in="$(project_load_plugin_sources "$project_ruler")"

  # 1) Plugin sources (only if opt-in)
  if [[ "$opt_in" == "true" ]]; then
    while IFS=$'\t' read -r ns ruler; do
      [[ -z "$ns" ]] && continue
      local dir
      dir="$(dirname "$ruler")"
      while IFS=$'\t' read -r id inject; do
        [[ -z "$id" ]] && continue
        id_is_disabled "$id" "$disable_list" && continue
        printf '%s\t%s\n' "$id" "$dir/$inject"
      done < <(get_always_rules_ns "$ruler" "$ns")
    done < <(find_plugin_sources)
  fi

  # 2) Project source (always, disable applied for consistency)
  if [[ -n "$project_ruler" ]]; then
    local proj_dir
    proj_dir="$(dirname "$project_ruler")"
    while IFS=$'\t' read -r id inject; do
      [[ -z "$id" ]] && continue
      id_is_disabled "$id" "$disable_list" && continue
      printf '%s\t%s\n' "$id" "$proj_dir/$inject"
    done < <(get_always_rules_ns "$project_ruler" "")
  fi
}

# _ruler_emit_tool <namespace> <ruler_file> <disable_list>
#   Internal helper: emit JSONL rules from one source with dir attached.
#   Defined at top-level (not nested inside another function) to avoid
#   bash scope leakage after first call to load_merged_tool.
_ruler_emit_tool() {
  local ns="$1" ruler="$2" disable_list="$3"
  local dir
  dir="$(dirname "$ruler")"
  get_tool_rules_ns "$ruler" "$ns" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local id
    id="$(echo "$line" | jq -r '.id')"
    id_is_disabled "$id" "$disable_list" && continue
    echo "$line" | jq -c --arg dir "$dir" '. + {dir: $dir}'
  done
}

# load_merged_tool
#   Emit JSONL of tool rules (non-always) with fields {id, when, inject, dir}
#   where `dir` is the absolute path of the rule's source directory
#   (used by on-pre-tool.sh to cat inject files).
load_merged_tool() {
  local project_ruler disable_list="" opt_in="false"
  project_ruler="$(find_ruler 2>/dev/null || true)"
  if [[ -n "$project_ruler" ]]; then
    disable_list="$(get_disabled_ids "$project_ruler")"
    opt_in="$(project_load_plugin_sources "$project_ruler")"
  fi

  if [[ "$opt_in" == "true" ]]; then
    while IFS=$'\t' read -r ns ruler; do
      [[ -z "$ns" ]] && continue
      _ruler_emit_tool "$ns" "$ruler" "$disable_list"
    done < <(find_plugin_sources)
  fi

  [[ -n "$project_ruler" ]] && _ruler_emit_tool "" "$project_ruler" "$disable_list"
}

# _ruler_sha1
#   Portable sha1: prefer shasum (macOS default), fall back to sha1sum (most Linux),
#   fall back to openssl as last resort. Reads from stdin.
_ruler_sha1() {
  if command -v shasum >/dev/null 2>&1; then
    shasum | awk '{print $1}'
  elif command -v sha1sum >/dev/null 2>&1; then
    sha1sum | awk '{print $1}'
  else
    openssl dgst -sha1 | awk '{print $NF}'
  fi
}

# ruler_cache_path
#   Absolute path to this project's cache file.
#   Key on the ruler-file's directory (stable across cd into subdirs), or
#   fall back to $PWD when no project ruler exists (env-var-only mode).
ruler_cache_path() {
  local base h
  base="$(find_ruler 2>/dev/null || true)"
  [[ -n "$base" ]] && base="$(dirname "$base")" || base="$PWD"
  h="$(printf '%s' "$base" | _ruler_sha1)"
  echo "/tmp/ruler-cache-$h.json"
}

# ruler_cache_clear
ruler_cache_clear() {
  rm -f "$(ruler_cache_path)"
}

# ruler_cache_key
#   Combined mtime hash of all inputs that affect merged output.
ruler_cache_key() {
  local files=()
  local project_ruler
  project_ruler="$(find_ruler 2>/dev/null || true)"
  [[ -n "$project_ruler" ]] && files+=("$project_ruler")
  [[ -f "$HOME/.claude/plugins/installed_plugins.json" ]] \
    && files+=("$HOME/.claude/plugins/installed_plugins.json")
  while IFS=$'\t' read -r ns ruler; do
    [[ -n "$ruler" ]] && files+=("$ruler")
  done < <(find_plugin_sources 2>/dev/null)

  local mtimes=""
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      mtimes+="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null):"
    fi
  done
  printf '%s' "$mtimes" | _ruler_sha1
}

# load_merged_always_cached
#   Wraps load_merged_always with mtime-keyed /tmp cache.
load_merged_always_cached() {
  local cache_file key_now cached_key
  cache_file="$(ruler_cache_path)"
  key_now="$(ruler_cache_key)"

  if [[ -f "$cache_file" ]]; then
    cached_key="$(jq -r '.key // ""' "$cache_file" 2>/dev/null)"
    if [[ "$cached_key" == "$key_now" ]]; then
      jq -r '.always[] | [.id, .path] | @tsv' "$cache_file" 2>/dev/null
      return 0
    fi
  fi

  # Miss — rebuild both always AND tool in one pass so later
  # load_merged_tool_cached calls are free reads. This doubles cold-start cost
  # vs building only what was asked, but cuts steady-state hook overhead.
  local always_json tool_json
  always_json="$(load_merged_always | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {id: .[0], path: .[1]})')"
  tool_json="$(load_merged_tool | jq -s '.')"

  jq -n --arg k "$key_now" --argjson a "$always_json" --argjson t "$tool_json" \
    '{key:$k, always:$a, tool:$t}' > "$cache_file" 2>/dev/null || true

  printf '%s\n' "$always_json" | jq -r '.[] | [.id, .path] | @tsv'
}

# load_merged_tool_cached
load_merged_tool_cached() {
  local cache_file key_now cached_key
  cache_file="$(ruler_cache_path)"
  key_now="$(ruler_cache_key)"

  if [[ -f "$cache_file" ]]; then
    cached_key="$(jq -r '.key // ""' "$cache_file" 2>/dev/null)"
    if [[ "$cached_key" == "$key_now" ]]; then
      jq -c '.tool[]' "$cache_file" 2>/dev/null
      return 0
    fi
  fi

  # Force rebuild via load_merged_always_cached (which also writes tool cache)
  load_merged_always_cached >/dev/null
  jq -c '.tool[]' "$cache_file" 2>/dev/null || true
}
