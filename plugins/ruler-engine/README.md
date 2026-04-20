# ruler-engine

Pluggable rule-injection engine for Claude Code. Loads `.claude-rules/ruler.yml` from your project and injects rules into Claude's prompt via `UserPromptSubmit` / `PreToolUse` hooks.

**Engine only. Zero business rules.** You author rules in your own project.

## Install

```bash
/plugin marketplace add https://github.com/<your-user>/ruler-engine
/plugin install ruler-engine
```

### Dependencies

```bash
brew install yq jq     # macOS
# python3 ships with macOS
```

## Quick Start

```bash
# in your project root
mkdir -p .claude-rules/rules
cp ~/.claude/plugins/cache/.../ruler-engine/templates/ruler.yml .claude-rules/
cp ~/.claude/plugins/cache/.../ruler-engine/templates/rules/example.md .claude-rules/rules/project-overview.md
# edit to taste
ruler-engine-lint
```

## How It Works

- **`when: always`** → injected on every user prompt
- **`when: {tool: Edit, file_glob: "**/*.vue"}`** → injected when Claude is about to Edit a .vue file
- **`when: [{...}, {...}]`** → OR of conditions; any match triggers injection

## Authoring Rules

See the embedded `ruler-authoring` skill (activates automatically when you edit `.claude-rules/*`). Or read `skills/ruler-authoring/SKILL.md` in this repo.

## CLI

```bash
ruler-engine-lint                                    # validate ruler.yml
ruler-engine-dry-run --always                        # preview UserPromptSubmit injection
ruler-engine-dry-run --tool=Edit --file=src/x.vue    # preview PreToolUse injection
```

## Limits

- `when: always` rules: max 5 (lint enforced)
- rule file size: >500 bytes → lint warning
- hook timeout: 1000ms (configured in hooks.json)
- platforms: macOS/Linux (Windows not supported)

## Security

Rule file content is injected directly into Claude's prompt. Treat `.claude-rules/` as code — review in git before merging.

## Development

```bash
brew install bats-core
bats tests/unit
```
