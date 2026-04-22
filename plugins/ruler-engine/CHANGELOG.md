# Changelog

## 0.2.0 — 2026-04-22

- Feat: plugin-bundled rule sources (opt-in via project `load_plugin_sources: true`)
- Feat: `disable: [<id-glob>]` filter in project ruler.yml
- Feat: `RULER_EXTRA_SOURCES` env var for dev/testing (`ns1:/path/ruler.yml,...`)
- Feat: `ruler-engine-lint --file <path>` mode for plugin-author CI
- Feat: `ruler-engine-dry-run --sources` lists all discovered sources
- Feat: mtime-keyed `/tmp/ruler-cache-*.json` avoids repeated yq parsing in hooks
- Warn: aggregate always-rules size >2KB; dangling `disable:` ids
- Backward-compatible: no behavior change without explicit opt-in

## 0.1.0 (2026-04-19)

### Added
- `UserPromptSubmit` hook injects `when: always` rules from `.claude-rules/ruler.yml`
- `PreToolUse` hook matches `{tool, file_glob, command_regex}` conditions (OR-semantics for arrays)
- `ruler-engine-lint` validates ruler schema, file refs, and limits
- `ruler-engine-dry-run` simulates hook invocation for local testing
- Embedded `ruler-authoring` skill teaches rule format + CLI
- Templates for ruler.yml + rule files

### Supported tools (first version)
- Edit, Write, Read (with `file_glob`)
- Bash (with `command_regex`)

### Limits
- 5 `when: always` rules max (lint enforced)
- 500 byte per rule file (lint warning)
- 1000ms hook timeout
- macOS / Linux only
