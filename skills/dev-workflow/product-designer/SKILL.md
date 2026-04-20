---
name: product-designer
description: 产品设计编排器。当用户意图是产品阶段任务时触发——关键词包括"写需求""新需求""加一个功能""加需求""新功能""做一个""新做""增加""开发一个需求""写 PRD""拆需求""分解""可行性""评估"等。分流到 prd-writer / requirement-splitter / feasibility-assessor 三个子 skill，并在子 skill 完成后更新 _overview.md
---

# Product Designer — 产品设计主编排

## 何时使用

- 用户意图是产品阶段任务（不是写代码 / 跑测试），常见自然语言信号：
  - "写需求" / "新需求" / "写 PRD" / "起一个需求"
  - "加一个功能" / "加需求" / "新功能" / "新做一个" / "增加一个" / "开发一个需求"
  - "拆需求" / "分解需求" / "把这份 PRD 拆开" / "split"
  - "可行性" / "评估这个需求" / "看看能不能做" / "feasibility"
- 用户提供了 PRD、原型截图、Figma 链接，或指名一个子需求目录让做可行性评估。

### 不适用场景

- 用户要写代码 / 开发 / 实现 → 交给 `fullstack-builder`。
- 用户要生成测试 / 跑测试 → 交给 `test-runner`。

## 前置检查（Preflight）

**必须**先执行 `../../_shared/preflight.md` 定义的全部步骤（**Step 1 → 2 → 2.5 → 3.0 → 3**）：

1. **Step 1** superpowers **硬依赖**检测；未装直接硬 fail 并输出引导话术，**禁止进入主流程**（不再有"降级模式"）。
2. **Step 2** 项目适配：Read `../../_shared/project-adapter.md`，按 Part 1→2→3→4 绑定下游变量。
3. **Step 2.5** 记录 `session_base = git rev-parse HEAD`（贯穿后续 diff 用途）。
4. **Step 3.0** 推断 `<target-requirement-dir>`（仅 prd-writer / requirement-splitter 入口可跳过；feasibility-assessor 入口必须执行）。
5. **Step 3** 输入就绪检查（按 preflight §3.1 product-designer 分支）。

**严禁跳过 Preflight**。即便用户追问紧急也不例外。

## 主流程

### Step A — 分流到子 skill

| 用户信号 | 进入子 skill | 必要输入条件 |
|---------|-------------|-------------|
| "写需求 / 新需求 / 写 PRD / 起一个需求" + 单一小功能 | `subskills/prd-writer/` | 至少一种需求来源（口述 / 截图 / Figma / 本地文件） |
| "拆需求 / 分解 / split / 批量创建子需求" + 大 PRD 或多模块素材 | `subskills/requirement-splitter/` | 大需求来源（文件 / 截图 / Figma / 长文本） |
| "可行性 / 评估 / feasibility" + 指定 `{编号}-{功能名}`（或从 `_overview.md` 推断） | `subskills/feasibility-assessor/` | `<target-requirement-dir>/需求.md` 存在 |
| **信号不明确 / 多个关键词冲突 / 完全无信号** | **不自己选**，ask 用户 | — |

兜底话术（信号不明确时必用）：

```
我可以帮你做下面三件事之一，请选一个：
  【1】写一个新需求（单个功能）
       —— 你要新增一个功能 / 之前还没写过相关 PRD / 单一边界
  【2】把大 PRD / 设计稿拆成多个子需求
       —— 你已有大 PRD 或多模块设计稿，需要分解为多个独立可交付的小需求
  【3】评估某个已有子需求的可行性
       —— 已经存在 <编号>-<功能名>/ 目录与 需求.md，想看代码层面能不能做、风险如何
回复 1 / 2 / 3，或直接用一句话描述你想做什么。
```

**禁止**在用户未明确选择前擅自进入任何子 skill。

### Step B — 调用子 skill

**调用方式：Read 子 skill 的 `SKILL.md` 内容**（而不是通过 Skill 工具触发；subskills/ 嵌套能否被 Skill 工具自动发现有不确定性）：

- 撰写新需求：Read `<project_root>/.claude/skills/product-designer/subskills/prd-writer/SKILL.md` 并按其主流程执行。
- 拆需求：Read `<project_root>/.claude/skills/product-designer/subskills/requirement-splitter/SKILL.md`。
- 可行性：Read `<project_root>/.claude/skills/product-designer/subskills/feasibility-assessor/SKILL.md`。

每个子 skill 在自己的主流程中只使用 Preflight 已绑定的变量，不再重新探测路径或技术栈。

### Step C — 子 skill 完成后更新 `_overview.md`（**唯一写入方**）

**硬约束**：`_overview.md` 的写入由本主 skill 唯一负责。子 skill **只返回"期望写入数据"** 的结构化对象给主 skill，**不直接修改**该文件。

子 skill 返回结构示例：

```yaml
overview_update:
  action: append | update | bulk_init
  rows:
    - id: "001"
      name: "用户登录"
      status: "🔵 待开发"
      priority: "P1"
      depends_on: "无"
      note: "—"
```

主 skill 收到后执行**读-改-写算法**：

1. Read `<requirements_dir>/_overview.md`：
   - 文件不存在 → 创建并写入表头：
     ```
     # 需求总览
     
     | 编号 | 名称 | 状态 | 优先级 | 依赖 | 备注 |
     |------|------|------|--------|------|------|
     ```
   - 文件存在但表头格式异常 → 按 `_shared/file-conventions.md` §5 走"提示覆盖 / 备份后覆盖 / 取消"。
2. 按 `action` 处理 `rows`：
   - `append`：追加新行（去重：编号已存在则改用 `update`）。
   - `update`：定位 `编号` 列匹配的行，原地修改其他列。
   - `bulk_init`：requirement-splitter 批量产出场景，整体替换或与现有合并（按子 skill 返回的合并策略）。
3. 写回 `_overview.md`。

子 skill 与主 skill 的对应：

| 子 skill | 子 skill 返回 | 主 skill 动作 |
|---------|---------------|---------------|
| `prd-writer` 完成 | `action: append` + 1 行 | 追加该行（首次创建表头） |
| `requirement-splitter` 完成 | `action: bulk_init` + N 行 | 按其合并策略（覆盖/合并/跳过）写入 |
| `feasibility-assessor` 完成 | `action: update` + 1 行（`status: 🟡 评估中` + 备注） | 状态 🔵 → 🟡（或保留 🟡） |

状态符严格使用 `_shared/file-conventions.md` §4.1 定义的五个符号。

### Step D — 汇报与下一步建议

每次主流程结束，向用户输出简短总结：

- 做了什么（哪个子 skill，产出了哪些文件，绝对路径）
- 下一步建议（例如："可以调用 /product 对 042-xxx 做可行性评估" / "可以 /fullstack 进入开发"）

## 子 skill 调用

| 子 skill | 路径 | 职责摘要 |
|---------|------|---------|
| `prd-writer` | `<project_root>/.claude/skills/product-designer/subskills/prd-writer/SKILL.md` | 单需求双产出：PRD.md + 需求.md |
| `requirement-splitter` | `<project_root>/.claude/skills/product-designer/subskills/requirement-splitter/SKILL.md` | 大需求拆分 + 批量产出 + `_overview.md` |
| `feasibility-assessor` | `<project_root>/.claude/skills/product-designer/subskills/feasibility-assessor/SKILL.md` | 中等深度可行性评估 → `可行性.md` |

**调用协议统一**：Read 子 skill 的 SKILL.md 文件内容，主 skill 按其内部编号步骤执行，不使用 Skill 工具。

## 产出规范

主 skill 自己**不产出**任何需求文档；产物由子 skill 创建。主 skill 只对 `_overview.md` 负责（见 Step C）。

涉及路径全部用语义变量：
- `<project_root>` / `<requirements_dir>` / `<target-requirement-dir>` / `<product_dir>` / `<backend_dir>` / `<frontend_dir>`
- **严禁**在 SKILL.md 内硬编码 `shangyunbao-arena` / `asms` / `taikeduo` / `product/` / `backend/` 等具体项目名或裸目录名。

## 失败处理

| 情况 | 处理 |
|------|------|
| Preflight Step 1 superpowers 未装 | 硬 fail，输出引导话术，终止本 skill |
| Preflight Step 2 路径 / 栈无法自动识别 | 按 `_shared/project-adapter.md` 优先级 3 ask 用户，**不默默取默认值** |
| Preflight Step 3.0 无法推断 `<target-requirement-dir>` | 列表展示 `<requirements_dir>/` 下所有子需求让用户选 |
| Preflight Step 3 目标需求目录或 `需求.md` 不存在（可行性评估场景） | 阻断，ask 用户补充或先走 `prd-writer` |
| 分流信号不明确 | 强制 ask 用户二/三选一，不擅自分流 |
| 子 skill 执行中失败 | 主 skill 汇总错误点，保留已成功产物，向用户报告下一步 |
| `_overview.md` 更新冲突（格式不兼容 / 行已存在） | 按 `_shared/file-conventions.md` §5 走提示覆盖 / 合并策略 |

## 禁止事项

- **不直接生成需求文档**：所有 `PRD.md` / `需求.md` / `可行性.md` 必须走子 skill 产出，主 skill 严禁自己写这三份文件中的任何内容。
- **不跳过 Preflight**。
- **不擅自分流**：用户信号不明确必须 ask。
- **不通过 Skill 工具调用子 skill**；统一 Read 子 skill 的 SKILL.md（避免 subskills/ 嵌套被 Skill 工具自动发现的不确定性）。
- **不硬编码项目名 / 路径 / 技术栈**；全部引用 Preflight 绑定的语义变量。
- **不在未收到确认的情况下覆盖已有文件**；走 `_shared/file-conventions.md` §5 提示覆盖模板。
- **不使用非 schema 规定的状态符号**；严格使用五个表情符。
