# karpathy-rules

4 behavioral guardrails for Claude Code, adapted from Andrej Karpathy-inspired writing collected in [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills). Ships as a ruler-engine plugin source.

## Requires

- `ruler-engine >= 0.2.0` (plugin source discovery)
- `yq`, `jq`, `python3` (ruler-engine deps)

> The marketplace manifest schema has no `dependencies` field, so this dependency is documented here only. `/plugin install karpathy-rules` without `ruler-engine` will install successfully but rules will never inject.

## Rules

| ID | Trigger | Summary |
|----|---------|---------|
| `think-before-coding` | every prompt | Surface assumptions, ask when unclear |
| `simplicity-first` | Edit/Write | Minimum code, no speculative features |
| `surgical-changes` | Edit | Don't touch unrelated code |
| `goal-driven-execution` | every prompt | Translate tasks into verifiable goals |

## Enable

After installing both plugins, in any project's `.claude-rules/ruler.yml`:

```yaml
version: 1
load_plugin_sources: true
rules: []
```

Verify:
```bash
ruler-engine-dry-run --sources
ruler-engine-dry-run --always   # should show think-before-coding + goal-driven-execution
```

## Opt-out per rule

```yaml
disable:
  - "karpathy-rules/simplicity-first"  # kill one
  - "karpathy-rules/*"                  # kill all
```

## Attribution

Rule content adapted from upstream under MIT license. See `LICENSE` for upstream copyright and our packaging notice.
