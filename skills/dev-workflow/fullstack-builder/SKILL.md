---
name: fullstack-builder
description: 全栈开发编排器。当用户意图进入实现阶段时触发——关键词包括"实现需求""开始开发""做这个子需求""把需求做了""前后端一起实现""落地 <编号>-<功能名>"等。读取 需求.md/可行性.md 后编排 superpowers 的 writing-plans / TDD / verification，驱动 self-review 多轮 loop，再调 change-summarizer 产出 改动.md 并推进状态
---

# Fullstack Builder — 全栈开发主编排

> **强制依赖 superpowers**：本 skill 不再支持降级模式。Preflight 检测未装即硬 fail，禁止进入主流程。

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 用户意图进入实现阶段（不是写需求 / 跑测试），常见信号：
  - "实现需求" / "开始开发" / "开发这个子需求" / "把需求做了"
  - "前后端一起实现" / "落地 <编号>-<功能名>"
- `<target-requirement-dir>/需求.md` 已经存在，状态为 🔵 待开发 / 🟡 评估中；用户明确要进入开发阶段。

### 不适用场景

- 用户只想写需求 / 拆需求 / 做可行性评估 → 交给 `product-designer`。
- 用户想生成测试用例 / 跑测试 / 做接口自动化 → 交给 `test-runner`。
- 本目录下尚无 `需求.md`：**阻断**，先走 `product-designer` 产出需求文档。

## 前置检查（Preflight）

**必须**先执行 `../_shared/preflight.md` 定义的全部步骤（**Step 1 → 2 → 2.5 → 3.0 → 3**）：

1. **Step 1** superpowers **硬依赖**检测；未装直接硬 fail 并输出引导话术，**禁止进入主流程**。
2. **Step 2** 项目适配：Read `../_shared/project-adapter.md`，按 Part 1→2→3→4 绑定下游变量：`project_root` / `requirements_dir` / `backend_dir` / `frontend_dir` / `test_dir` / `backend_stack` / `frontend_stack` / `test_backend_stack` / `test_frontend_stack` / `backend_cwd` / `frontend_cwd` / `test_cwd` / `code_conventions`。
3. **Step 2.5** 记录 `session_base = git rev-parse HEAD`。**全程**所有 git diff 必须用 `git diff <session_base>`，不得用 `git diff HEAD`。
4. **Step 3.0** 推断 `<target-requirement-dir>`（**强制**，不得跳过）。
5. **Step 3** 输入就绪检查（按 preflight §3.2 fullstack-builder 分支）：
   - **强制**：`<target-requirement-dir>/需求.md` 存在。
   - **推荐**：`<target-requirement-dir>/可行性.md` 存在；不存在则警告并询问"是否先走 feasibility-assessor"。
   - 至少 `backend_stack` / `frontend_stack` 之一非 N/A（全 N/A 阻断）。
   - **N/A 短路**：`frontend_stack = N/A` 时跳过所有前端就绪判定（按 `_shared/file-conventions.md` §8）。

**严禁跳过 Preflight**。即便用户反复催促，也必须完整执行。

## 主流程

整体六个阶段，按编号顺序执行。

```
Step 1 读输入
  → Step 2 规划（superpowers:writing-plans）
    → Step 3 实现（superpowers:test-driven-development）
      → Step 4 verification（superpowers:verification-before-completion）
        → Step 5 self-review loop（必经，独立 subagent 派发）
          → Step 6 change-summarizer（必经）
            → Step 7 更新 _overview.md + 汇报
```

### Step 1 — 读输入

- Read `<target-requirement-dir>/需求.md`，按 `../_shared/requirement-schema.md` §1 解析全部字段（FP-N、AC-N、影响面提示、头部元信息）。
- Read `<target-requirement-dir>/可行性.md`（若存在）；提取"涉及文件清单 / 推荐实现方向 / 技术风险"，作为 Step 2 输入。
- 若 `需求.md` 解析到缺章节或格式异常：按 `_shared/requirement-schema.md` §3.2 询问用户（禁止擅自回填）。

### Step 2 — 规划阶段（superpowers:writing-plans）

**目标**：产出 `<target-requirement-dir>/plan.md`（路径见 `_shared/file-conventions.md` §1.1 第 (6) 项）。

**调用方式**：用 Skill 工具触发 `superpowers:writing-plans`，通过 args 传入 `<target-requirement-dir>` 的**绝对路径**。该子 skill 自己会 Read 该目录下的 `需求.md` / `可行性.md`，并按其内部 prompt 产出 `plan.md`。**不要**在 args 里塞需求全文（Skill 工具的 args 是字符串，不适合大段上下文；让被调 skill 自己读文件）。

plan 要求（向被调 skill 通过 args 简短说明）：

- 按 FP-N 组织任务节；每节含"实现步骤 / 测试步骤 / 完成条件"。
- 每步粒度 ≤ 一次 TDD 循环（红 → 绿 → 重构）。
- 前后端一体规划（若双端都涉及）；明确接口契约（方法 / 路径 / 请求 / 响应 / 错误码 / 鉴权）；纯后端项目 (`frontend_stack = N/A`) 不规划前端任务。

**覆盖策略**：`plan.md` 已存在 → 按 `_shared/file-conventions.md` §5 的"提示覆盖"。

### Step 3 — 实现阶段（superpowers:test-driven-development）

**目标**：按 `plan.md` 把代码改完，单任务闭环推进。

**调用方式**：用 Skill 工具触发 `superpowers:test-driven-development`（或 `superpowers:executing-plans`），通过 args 传入 `<target-requirement-dir>/plan.md` 的绝对路径与 `<target-requirement-dir>` 工作目录。

- 代码规范由被调 skill 通过读 Preflight 绑定的 `code_conventions` 自动遵守；本 skill 不重复内联 TDD 纪律（这是 superpowers 的职责）。
- **N/A 短路**：`frontend_stack = N/A` → plan 中本就无前端任务，本步骤自然不动前端。

### Step 4 — verification 阶段（superpowers:verification-before-completion）

**目标**：在声称"做完"之前拿到客观证据。

**调用方式**：用 Skill 工具触发 `superpowers:verification-before-completion`。

**verification 命令的执行目录（cwd）**：按 `_shared/project-adapter.md` Part 4.2 绑定：

- 后端 verification 命令默认 `cwd = <backend_cwd>`（即 `<backend_dir>`）。
- 前端 verification 命令默认 `cwd = <frontend_cwd>`（即 `<frontend_dir>`）。
- monorepo / 异构场景由 `config.yml` 显式覆盖。

**N/A 短路**：

- `frontend_stack = N/A` → 跳过前端 verification 命令组（不跑 `npm test` / `vitest` 等）。
- `backend_stack = N/A` → 跳过后端 verification 命令组。

**要求**：每条命令的**实际输出**必须被看到，不得凭记忆断言"应该通过"。命令失败 → 回到 Step 3 修复，**不得**带着失败进入 Step 5。

### Step 5 — self-review loop（必经；必须派发独立 subagent）

**硬约束**：**主会话不得自行执行 self-review**；必须用 Agent 工具派发一个独立的 general-purpose / code-reviewer subagent 来执行 `subskills/self-review/SKILL.md`，避免"自己给自己打勾"的确认偏误。

#### 5.1 派发协议（**7 字段最小上下文**）

每轮派发前，主会话在一条消息中通过 Agent 工具**派发**子 agent。Agent prompt 必须打包以下 **7 个字段**（任一缺失子 agent 应回传"上下文不足"）：

| 字段 | 内容 | 来源 |
|------|------|------|
| `target_requirement_dir` | `<target-requirement-dir>` 绝对路径 | Preflight Step 3.0 |
| `session_base` | git base commit hash | Preflight Step 2.5 |
| `round_n` | 当前轮次（1, 2, 3, ...） | 主 skill loop 计数 |
| `code_conventions` | Preflight Step 2 绑定的代码规范全文（可拼接） | Preflight |
| `superpowers_available` | 必为 `true`（否则 Preflight 已硬 fail） | Preflight Step 1 |
| `backend_dir` | 后端代码目录（或 `N/A`） | Preflight Step 2 |
| `frontend_dir` | 前端代码目录（或 `N/A`） | Preflight Step 2 |

派发 prompt 末尾指令：

```
读 <project_root>/.claude/skills/fullstack-builder/subskills/self-review/SKILL.md 并按其主流程执行；
所有 git diff 使用 `git diff <session_base>`（不得用 git diff HEAD）；
追加结果到 <target-requirement-dir>/自审报告.md（追加 Round-N，不得覆盖已有内容）；
完成后回传问题清单 P0/P1 摘要给主 skill。
```

#### 5.2 循环与退出条件

每轮结束后主会话读取 `自审报告.md` 的 Round-N 节，抽取 P0 / P1 问题清单：

- **有 P0 或 P1**：进入"修复 → 再 verification → 再派发"循环；每进入新一轮，Round 编号 +1，**追加**到 `自审报告.md`（**禁止覆盖**，见 `_shared/file-conventions.md` §5.2）。
- **退出条件**（三选一即退出 loop）：
  1. **无新问题**：当轮自审结论为"无 P0/P1"。
  2. **达最大轮次**：`options.self-review-max-rounds`（默认 **3**；可由 `config.yml` 覆盖）。达上限仍有 P0 时，**阻断 Step 6**，把遗留问题显式汇报给用户决定（修 / 放过 / 终止）。
  3. **用户手动终止**：用户在任一轮间隙明确说"停 / 够了 / 不再审"。

#### 5.3 Round-N 写入约定

- 每轮以 `## Round N - YYYY-MM-DD HH:mm` 为二级标题追加到 `自审报告.md`。
- 首次建档时写入一级标题 `# 自审报告 - <编号> - <功能名>`，再从 `Round 1` 开始。
- 详细内部结构见 `subskills/self-review/SKILL.md` §产出规范。

### Step 6 — change-summarizer（必经节点；不跳过）

**硬约束**：Step 5 退出 loop 后**必须**进入 Step 6。即使用户说"省略 / 跳过"，也要向用户解释"下游 test-runner 依赖 `改动.md` 作为唯一权威输入"，争取用户同意；若用户坚决拒绝，**仍然至少**产出一个最小 `改动.md`（按 schema 必填字段填 `无`），不得完全不产出。

**调用方式**：主会话直接 **Read** `<project_root>/.claude/skills/fullstack-builder/subskills/change-summarizer/SKILL.md`（与 product-designer 主 skill 保持一致的子 skill 调用协议），按其主流程执行；产物路径 `<target-requirement-dir>/改动.md`。

change-summarizer 内部所有 git diff **必须**用 `git diff <session_base>`，由本主 skill 在调用时把 `session_base` 显式传入子 skill 的执行上下文（写在主会话的提示里）。

### Step 7 — 更新 `_overview.md` 并汇报

**统一协议**：本步骤的"读-改-写"算法严格遵循 [`../_shared/file-conventions.md`](../_shared/file-conventions.md) §10「`_overview.md` 写入算法（统一协议）」；本主 skill 仅作为 §10.3 "触发点"表中 `fullstack-builder` 行的执行者，不重复实现算法逻辑。

- 把目标子需求在 `<requirements_dir>/_overview.md` 的状态从 🟢 开发中 → 🟣 测试中（Step 6 成功时）。
- 若 Step 5 loop 因"达最大轮次且仍有 P0"而阻断 Step 6：状态**保留** 🟢 开发中，备注列写入"self-review Round-<N> 存在 P0：<简述>，待人工决策"。
- "首次"判定：基于 `_overview.md` 当前状态，若已是 🟣 / ✅ 则不重复推进；其他状态则按链路推进一步。
- 汇报向用户输出的最小信息：
  - 当前编号 / 功能名
  - 每阶段产物绝对路径（plan.md / 改动.md / 自审报告.md / 本次 verification 命令摘要）
  - 下一步建议（如"可以触发 test-runner 进入测试阶段"）

## 子 skill 调用

| 子 skill | 路径 | 职责摘要 | 调用方式 |
|---------|------|---------|---------|
| `self-review` | `<project_root>/.claude/skills/fullstack-builder/subskills/self-review/SKILL.md` | 独立 subagent 审查多维度，追加 `自审报告.md` | **Agent 工具派发** subagent，让其 Read 该 SKILL.md 执行 |
| `change-summarizer` | `<project_root>/.claude/skills/fullstack-builder/subskills/change-summarizer/SKILL.md` | 产出 `改动.md` 面向 test-runner | 主会话直接 Read SKILL.md 按其主流程执行 |

**两个子 skill 的调用协议差异**：

- `self-review` **必须** Agent 派发，不能在主会话执行（独立性硬约束）。
- `change-summarizer` 可在主会话执行（不涉及"自我背书"问题，只做客观归档）。

主 skill 调用 superpowers 子 skill（`writing-plans` / `test-driven-development` / `verification-before-completion`）一律通过 **Skill 工具**触发；args 仅传必要的"目录 / 文件路径 + 一句话上下文"，让子 skill 自己 Read 文件。

## 产出规范

主 skill 自己**不直接写**任何面向最终文档的内容；所有产物由以下渠道落盘：

| 产物 | 路径 | 产生者 | 覆盖策略 |
|------|------|--------|---------|
| `plan.md` | `<target-requirement-dir>/plan.md` | superpowers:writing-plans | 提示覆盖 |
| 代码改动 | `<backend_dir>` / `<frontend_dir>` 内 | superpowers:test-driven-development | 按代码仓库本身 |
| `自审报告.md` | `<target-requirement-dir>/自审报告.md` | Step 5 的独立 subagent | **追加**（Round-N） |
| `改动.md` | `<target-requirement-dir>/改动.md` | Step 6 子 skill | 提示覆盖 |
| `_overview.md` 状态列 | `<requirements_dir>/_overview.md` | Step 7 | 行级更新 |

所有路径在 SKILL.md 与子 skill 文本中**只用语义变量**：`<project_root>` / `<requirements_dir>` / `<target-requirement-dir>` / `<backend_dir>` / `<frontend_dir>` / `<test_dir>`。

## 失败处理

| 情况 | 处理 |
|------|------|
| Preflight Step 1 superpowers 未装 | 硬 fail，输出引导话术，终止本 skill |
| Preflight Step 3 `需求.md` 缺失 | 阻断，ask 用户先走 `product-designer/prd-writer` |
| Preflight Step 3 `可行性.md` 缺失 | 警告并询问是否先走 `feasibility-assessor`；用户坚持继续则记录风险 |
| Step 2 plan 与可行性冲突 | 保留可行性结论为底线，在 plan.md 里以"偏离说明"节显式记录，征询用户同意 |
| Step 3 verification 反复失败 | 回到 Step 2 调整 plan，或调用 `superpowers:systematic-debugging` |
| Step 5 subagent 派发失败（上下文缺失 / 工具不可用） | **不得降级到主会话自审**；先补齐 7 字段派发上下文，再重试 |
| Step 5 subagent 回传"diff 为空" | **不视为通过**；检查 `session_base` 是否正确绑定，未正确则补齐再派发 |
| Step 5 达 max-rounds 仍有 P0 | 阻断 Step 6；把问题清单原样贴给用户，请求决策（修 / 放过并记录 / 终止） |
| Step 6 `改动.md` schema 校验失败 | 回到子 skill 修复；不放出格式不合规的 `改动.md` |
| Step 7 `_overview.md` 不存在 | 创建文件写入表头（按 `_shared/file-conventions.md` §3.2），再写当前行 |

## 禁止事项

- **不得跳过 Preflight**，即便用户催促。
- **不得自动 git commit**：所有代码改动留在工作区，由用户自行决定提交时机、消息、是否拆分 commit；本 skill 所有阶段产出的文档落盘即可，不做 `git add` / `git commit` / `git push`。
- **不得假装 superpowers 已装**：硬依赖模式下，未装一定走 Preflight 硬 fail，不得继续。
- **不得使用 `git diff HEAD`**：所有 diff 用 `git diff <session_base>`。
- **不得跳过 Step 5 self-review**。即使 Step 4 verification 全绿，仍然必须进入 self-review loop。
- **不得在主会话执行 self-review**：必须 Agent 工具派发独立 subagent；否则失去独立性，视同未执行。
- **不得覆盖 `自审报告.md`**：多轮追加，Round-N 顺序严格递增（见 `_shared/file-conventions.md` §5.2）。
- **不得跳过 Step 6 change-summarizer**：它是 test-runner 的唯一权威输入；跳过会阻断下游 `test-runner`。
- **不得硬编码项目名 / 路径 / 技术栈**：全部引用 Preflight 绑定的语义变量。
- **不得在 verification 未看到实际命令输出时声称通过**：Step 4 要求有证据，凭记忆断言视为未 verification。
- **不得擅自回填 `需求.md` / `改动.md` 的缺失字段**：遇到缺章节按 schema §3.2 ask 用户。
