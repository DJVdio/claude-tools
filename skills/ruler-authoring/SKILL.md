---
name: ruler-authoring
description: Use when editing .claude-rules/ruler.yml or .claude-rules/rules/*.md files, or when the user asks to add/modify a project rule, write a ruler entry, or debug why a rule did not trigger. Teaches the ruler.yml schema, matching semantics, best practices, and the ruler-engine CLI (lint + dry-run).
---

# Ruler Authoring

Write rules that the `ruler-engine` plugin injects into Claude's prompt automatically.

## Format

`.claude-rules/ruler.yml`:

```yaml
version: 1
rules:
  - id: <unique-id>
    when: always                              # OR single condition OR array of conditions
    inject: rules/<rule-file>.md
```

### `when` 三种合法形态（互斥）

| 形态 | 含义 | 触发时机 |
|---|---|---|
| `always` | 无条件 | 每轮 UserPromptSubmit |
| `{tool: X, ...}` | 单条件 | PreToolUse，且工具=X 时 |
| `[{...}, {...}]` | 多条件 OR | PreToolUse，任一命中即触发 |

**不允许混合**：`[always, {...}]` 非法。

### `<condition>` 字段

- `tool`（必填）：`Edit` / `Write` / `Read` / `Bash`（首版仅此 4 个）
- `file_glob`：bash glob，匹配 `file_path`；与 Edit/Write/Read 搭配
  - 支持 `*`（单段通配）、`**`（跨目录）、`?`、`[abc]`
- `command_regex`：POSIX 正则，匹配 Bash 的 `command` 参数
- `file_glob` 和 `command_regex` 互斥

## Rule 文件结构（建议）

每条 rule 一个 md 文件，≤200 字，结构化：

```markdown
Rule: <一句话核心主张>
Why: <这条规则存在的原因 —— 历史教训 / 领域约束>
How to apply: <如何落到具体动作>
```

小粒度：一个文件一条规则，不要堆砌。

## 最佳实践

- `when: always` 数量 ≤5（每轮付 token 成本敏感）
- rule 文件 ≤500 字节（lint 超限警告）
- 宁可误报不漏报：`file_glob` 写宽一点，rule 正文自判边界
- 一条规则覆盖多场景 → 用 `when: [...]` 数组，不要复制粘贴
- 改完一定跑 `ruler-engine-lint`

## 工具链

```bash
# 校验当前项目的 ruler
ruler-engine-lint

# 模拟 UserPromptSubmit 注入
ruler-engine-dry-run --always

# 模拟 PreToolUse（Edit 场景）
ruler-engine-dry-run --tool=Edit --file=src/App.vue

# 模拟 PreToolUse（Bash 场景）
ruler-engine-dry-run --tool=Bash --command="mysql -u root"
```

## 调试

ruler.yml 顶层加 `debug: true`（后续版本）让 hook 在 stderr 输出匹配过程。当前版本用 `ruler-engine-dry-run` 手动模拟。

## 常见错误

- **规则不触发**：
  1. 先 `ruler-engine-dry-run` 模拟目标场景
  2. 检查 `tool` 名拼写（大小写敏感，必须是 `Edit` 不是 `edit`）
  3. 检查 `file_glob`：单 `*` 不跨目录，跨目录要 `**`
- **每次 Edit 都触发**：glob 太宽，收紧
- **token 涨了很多**：清点 `when: always` 规则，或缩减单条 rule 文件长度

## 安全注意

rule 文件内容会被 hook 注入到 Claude 的 prompt。**不要信任外部来源的 rule 文件**。`.claude-rules/` 必须经 git code review。
