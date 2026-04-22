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

## Plugin Sources (0.2.0+)

Third-party plugins can ship rules that load alongside your project's `.claude-rules/`. Two opt-in gates protect you from unexpected prompt injection:

### Plugin-side (author)

```json
// .claude-plugin/plugin.json
{ "name": "my-rules", "ruler": true, ... }
```

Place rules at `<plugin-root>/claude-rules/ruler.yml` + `claude-rules/rules/*.md`.

### Project-side (consumer)

```yaml
# .claude-rules/ruler.yml
version: 1
load_plugin_sources: true   # opt-in
disable:
  - "my-rules/verbose-rule"  # kill one rule
  - "other-plugin/*"         # kill an entire plugin's rules
rules: [ ... ]
```

IDs from plugin sources are auto-prefixed: `<plugin-name>/<id>`. Your project's own rules stay unprefixed.

### Dev override

`RULER_EXTRA_SOURCES="ns1:/abs/ruler.yml,ns2:/abs/other.yml"` appends sources without needing manifest flags. Handy during plugin development.

### Verifying

```bash
ruler-engine-dry-run --sources     # list discovered sources
ruler-engine-dry-run --always      # preview merged always-injection
ruler-engine-lint --file path/to/ruler.yml   # lint arbitrary file
```

### Trust note

Enabling `load_plugin_sources: true` means any installed plugin with `"ruler": true` can inject text into every prompt. Review plugins before enabling — they effectively run inside Claude's prompt.

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
