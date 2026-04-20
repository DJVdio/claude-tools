---
name: prd-writer
description: （内部子 skill，仅由 product-designer 主 skill 派发调用，不应被顶层直接触发）从零撰写单个子需求：收集口述/截图/Figma/本地文件输入，澄清后产出面向人的 PRD.md 和面向 AI 的严格结构化 需求.md
---

# PRD Writer — 单需求撰写

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身或本说明。**

## 何时使用

- 用户说"写需求 / 新需求 / 写 PRD / 起一个需求文档"且**只对应一个独立子需求**。
- 用户已经有一个明确的小范围功能要落地（不是大 PRD 需要拆分）。
- 输入来源：口述、原型截图、Figma MCP、本地文件（md/pdf/doc/png）中的**任意一种或多种组合**。

### 不适用场景

- 用户上传的是大 PRD / 多功能合集 → 交回主 skill 分流到 `requirement-splitter`。
- 用户要求对已有 `需求.md` 做技术可行性评估 → 交回主 skill 分流到 `feasibility-assessor`。
- 用户要写代码、SQL、接口设计、技术方案 → **拒绝**，本 skill 只产出需求，不出技术方案。

### 自我保护：仅由主 skill 派发

本子 skill **不应**被 Claude Code 顶层关键词直接触发。若发现进入本 skill 时 **没有** 主 skill `product-designer` 已绑定的 Preflight 上下文（`project_root` / `product_dir` / `requirements_dir` / `next_requirement_id` 等），**立即拒绝执行**并提示：

```
本 skill 是 product-designer 的内部子 skill。
请先用 product-designer 入口（说"写需求 / 加一个功能 / 新功能"等）触发，
让主 skill 完成 Preflight 后再进入本子 skill。
```

## 前置检查（Preflight）

本子 skill 由主 skill `product-designer/SKILL.md` 路由进入，主 skill **已经**完成 Preflight（见 `../../../_shared/preflight.md`）。本子 skill 直接使用以下已绑定变量：

- `project_root` / `product_dir` / `requirements_dir`
- `naming_style`（目录命名风格）
- `next_requirement_id`（下一个可用编号）
- `requirement_template_samples`（项目已有模板样例摘要）
- `code_conventions`（仅用于了解项目文档中/英文风格，不涉及代码）
- `superpowers_available`（必为 `true`，否则 Preflight 已硬 fail）

若上述变量有任何一个缺失，**停止执行**，让主 skill 先补齐 Preflight。

### 本子 skill 额外检查

1. 用户是否已经提供至少一种输入来源？若没有，询问："请提供需求来源（口述描述 / 截图路径 / Figma 链接 / 本地文件路径），至少一项"。
2. 确认任务确为"单需求"。若输入看起来明显是多功能合集（例如含有多个互不相关的页面/模块），提示："这看起来涉及多个子需求，建议改走 requirement-splitter。是否切换？"

## 主流程

### Step 1 — 多源输入收集

按用户提供的来源逐一处理：

| 来源 | 处理方式 |
|------|---------|
| 口述文本 | 直接作为需求叙述进入 Step 2 |
| 截图路径（本地图片） | Read 工具读入，提取文字/界面元素/交互 |
| Figma | 用 `mcp__figma__get_screenshot` + `mcp__figma__get_metadata`（若可用），提取画面与组件结构 |
| 本地文件（md / pdf / doc） | Read 工具读入；PDF 超过 10 页须按 `pages` 参数分批 |

把各来源的信息合并成一份"原始素材笔记"（内存中保留即可，不落盘）。

### Step 2 — 澄清（一次只问 1–2 个信息性问题）

**硬性规则：一次最多问 1–2 个问题**，避免用户被问题列表淹没。

按下面的"必填优先级"挑当前最缺的 1–2 项来问：

1. 目标用户与使用场景（"谁 / 什么时候 / 为什么用"）
2. 核心功能点边界（能做什么，不能做什么）
3. 验收标准（用户怎样算"用对了"）
4. 非功能需求（性能 / 安全 / 合规 / 兼容性）
5. 与现有功能的关系（影响面提示）

提问示例：

```
素材已收到。有两个问题确认一下：
1. <最关键的一个问题>
2. <次关键的一个问题>
```

用户回答后，再判断是否需要再问；**每轮仍然只问 1–2 条**，直到信息足以产出 `需求.md` 的每个必填字段。

**完成判定**：当所有 FP-N 都有"行为描述/输入/输出/异常"四要素的明确答案，且至少有 1 条 AC 时，进入 Step 3。

### Step 3 — 确定编号与目录名

- 编号：**直接使用** Preflight 已绑定的 `next_requirement_id`；**不自己**扫目录再算一遍。
- 目录名：`{next_requirement_id}-<功能名>`，`<功能名>` 风格沿用 `naming_style`（纯中文 / 短横线英文 / 拼音）。
  - `naming_style = 纯中文` + 编号 `042` → 例：`042-赛季积分重置`
  - `naming_style = 短横线英文` + 编号 `7` → 例：`7-season-score-reset`
- 向用户确认最终目录名（一次简短确认即可）。

### Step 4 — 产出两份文档

目标路径：`<requirements_dir>/<编号>-<功能名>/`，两份文件：

- `PRD.md`（面向人，完整版）
- `需求.md`（面向 AI，严格 schema）

若目录已存在或文件已存在，按 `../../../_shared/file-conventions.md` §5 的"提示覆盖"交互模板处理。

#### 4.1 PRD.md 模板（§1–§8 均为必写章节）

> 模板中所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符或括注的解释文字本身。

```markdown
# PRD - <编号> - <功能名>

> 产出日期：<YYYY-MM-DD>
> 作者：prd-writer（product-designer）
> 版本：v1

## §1 背景

<本需求出现的业务原因：痛点 / 数据 / 外部压力 / 合规要求。一段叙述。>

## §2 目标

<一句话目标>

- <子目标 1>
- <子目标 2>

## §3 用户故事

- <角色 A>：<As a ... I want ... So that ...>
- <角色 B>：<...>

## §4 方案设计（产品视角）

<界面草图引用 / 交互流程 / 主要页面与组件；本节不写技术方案 / 代码 / SQL / 接口。>

- <页面或流程 1>：<描述>
- <页面或流程 2>：<描述>

## §5 非功能需求

- 性能：<指标 / 阈值 / 评估方式>
- 安全：<鉴权 / 数据脱敏 / 权限要求>
- 兼容性：<浏览器 / 设备 / API 版本>
- 其它：<合规、可用性、可维护性等>

## §6 验收标准

- AC-1 <可测可观察的判定句>
- AC-2 <...>

## §7 风险与未决问题

- 风险：<已识别的实施 / 业务风险>
- 未决：<尚待用户或上下游确认的问题>

## §8 附录

- 原型截图 / Figma 链接：<URL 或路径>
- 参考文档：<URL 或路径>
- 相关需求编号：<编号列表 或 无>
```

#### 4.2 需求.md 模板（严格按 `_shared/requirement-schema.md`）

**字段顺序固定、章节标题不可重命名、缺失字段写 `无` / `N/A` 而非删除**。

> 模板中所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符。

```markdown
# 需求 - <编号> - <功能名>

> 状态：待开发
> 优先级：<P0 | P1 | P2>
> 工作量：待评估
> 前置依赖：<编号列表，逗号分隔；无依赖写"无">

## 背景

<≤ 200 字的简短叙述>

## 目标

- <目标 1>
- <目标 2>

## 功能点

### FP-1 <功能点名称>

- 行为描述：<...>
- 输入：<...>
- 输出：<...>
- 异常：<异常路径或"无">

### FP-2 <功能点名称>

- 行为描述：<...>
- 输入：<...>
- 输出：<...>
- 异常：<...>

## 验收标准

- [ ] AC-1 <...>
- [ ] AC-2 <...>

## 非功能需求

- 性能：<指标，无写"无">
- 安全：<...>
- 兼容性：<...>

## 影响面提示（产品视角）

- <可能触及的现有功能 1>
- <可能触及的现有功能 2>
```

#### 4.3 模板自适应（项目已有模板 vs schema 冲突）

`requirement_template_samples` 可能显示项目已有文档结构与 `_shared/requirement-schema.md` 不一致。处理策略：

1. **默认**采用 `_shared/requirement-schema.md` 的 schema（下游 skill 基于它解析，偏离会破坏 feasibility-assessor / change-summarizer / test-runner）。
2. 向用户展示冲突点并建议：

   ```
   项目现有需求模板与本 skill 的严格 schema 在以下点不同：
     - <差异 1>（如 现有用 "功能1" 编号，schema 用 "FP-1"）
     - <差异 2>（如 现有无 "影响面提示" 章节）
   建议采用 schema（下游工具可稳定解析）。是否同意？
     【1】采用 schema（推荐）
     【2】沿用项目现有格式（需手动保证下游 skill 能解析，不建议）
   ```

3. 用户坚持沿用项目旧格式时，**记录在 PRD.md §8 附录**并警告下游 skill 可能解析失败。

### Step 5 — 完成与回传（**不直接写 `_overview.md`**）

- 写入 `PRD.md` + `需求.md`。
- **不**直接修改 `<requirements_dir>/_overview.md`。
- 向主 skill 返回结构化数据，由主 skill 唯一负责写入 `_overview.md`：

```yaml
# 子 skill 完成回执
result:
  status: ok | partial | error
  paths:
    prd: <requirements_dir>/<编号>-<功能名>/PRD.md
    requirement: <requirements_dir>/<编号>-<功能名>/需求.md
overview_update:
  action: append
  rows:
    - id: "<编号>"
      name: "<功能名>"
      status: "🔵 待开发"
      priority: "<P0|P1|P2>"
      depends_on: "<编号列表 或 无>"
      note: "—"
notes:
  - <可选：模板冲突、用户警告等说明>
```

主 skill 收到后按其 Step C 的"读-改-写算法"处理 `_overview.md`。

## 产出规范

| 产物 | 路径 | 必填 |
|------|------|------|
| PRD.md | `<requirements_dir>/<编号>-<功能名>/PRD.md` | 是（§1–§8 全填；无内容写"无"） |
| 需求.md | `<requirements_dir>/<编号>-<功能名>/需求.md` | 是（字段顺序固定，不得删除章节） |

覆盖策略：两个文件都走"提示覆盖"（见 `_shared/file-conventions.md` §5）。

## 失败处理

| 情况 | 处理 |
|------|------|
| 用户不回答澄清问题或回答太少 | 不得强行产出；再追问或给出"最小可产出版本 + 明确 TODO"方案让用户确认 |
| 目录已存在 | 按 `_shared/file-conventions.md` §5.1 提示覆盖 |
| 用户只给了截图无法识别 | 要求补充文字说明，或承认素材不足、暂停产出 |
| Figma MCP 不可用 | 请用户提供截图导出 / 文本化设计说明替代 |
| 功能点拆不出独立 FP（粒度太粗） | 退回 Step 2 继续澄清，或建议改走 `requirement-splitter` |
| 进入本 skill 时无主 skill 上下文 | 拒绝执行，按"自我保护"节话术指引用户走主 skill |

## 禁止事项

- **不写代码、不写技术方案、不写 SQL、不写接口设计**。这些是 `feasibility-assessor` / `fullstack-builder` 的职责。
- **不自己推编号**，必须用 `next_requirement_id`。
- **不乱序章节**，不改章节标题。
- **不删字段**，缺失写 `无` / `N/A`。
- **不一次性问一大堆问题**，每轮澄清最多 1–2 个问题。
- **不照抄模板里的尖括号占位或括号注释**到产出文件中。
- **不直接写 `_overview.md`**，必须返回结构化数据给主 skill。
- **不被顶层 skill 列表直接触发**（自我保护节）。
- **不硬编码项目名 / 路径**。所有路径引用 `<requirements_dir>` 等语义变量。
- **不跳过 PRD.md 或 需求.md 任一份**；两份是一对，缺一不可。
