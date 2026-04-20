# Changelog

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
