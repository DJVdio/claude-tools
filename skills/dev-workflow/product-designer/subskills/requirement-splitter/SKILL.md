---
name: requirement-splitter
description: （内部子 skill，仅由 product-designer 主 skill 派发调用，不应被顶层直接触发）拆分大 PRD / 多模块设计稿 / 大需求文档为多个独立子需求，自动分配编号，依赖拓扑排序，用户确认后批量生成 PRD.md + 需求.md
---

# Requirement Splitter — 大需求拆分

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 用户上传 / 提供的素材是**大 PRD / 多模块设计稿 / 多需求合集**，需要拆为多个独立子需求。
- 用户明确说"拆需求 / 分解 / 拆分 / split / 把这份 PRD 拆开 / 把这个模块拆成多个子需求"。

### 不适用场景

- 单需求 → 走 `prd-writer`。
- 已有子需求做可行性评估 → 走 `feasibility-assessor`。

### 自我保护：仅由主 skill 派发

本子 skill **不应**被 Claude Code 顶层关键词（如"拆需求"）直接触发。若发现进入本 skill 时 **没有** 主 skill `product-designer` 已绑定的 Preflight 上下文（`project_root` / `requirements_dir` / `next_requirement_id` 等），**立即拒绝执行**并提示：

```
本 skill 是 product-designer 的内部子 skill。
请先用 product-designer 入口（说"拆需求 / 把 PRD 拆开"等）触发，
让主 skill 完成 Preflight 后再进入本子 skill。
```

## 前置检查（Preflight）

由主 skill `product-designer/SKILL.md` 路由进入。直接使用主 skill Preflight 已绑定的变量：

- `project_root` / `product_dir` / `requirements_dir`
- `naming_style` / `next_requirement_id` / `requirement_template_samples`
- `code_conventions`
- `superpowers_available`（必为 `true`）

任一变量缺失即停止。

### 本子 skill 额外检查

1. 用户是否已经提供大需求素材（文件路径 / 截图 / Figma 链接 / 长文本）？没有则 ask 补充。
2. `requirements_dir` 是否存在（不存在要让 Preflight 先处理路径创建）。

## 主流程（5 步）

整条流程采用 5 步骨架，所有产出路径与文件命名遵循 `_shared/file-conventions.md` 的约定。

```
Step 1 学模板  →  Step 2 收输入  →  Step 3 自动拆  →  Step 4 表格确认  →  Step 5 批量生成
```

### Step 1 — 学项目模板（复用 Preflight 已学）

直接使用 `requirement_template_samples`（Preflight Part 3.2 已学）。无样例时按 `_shared/requirement-schema.md` 默认 schema。

### Step 2 — 收输入（多源）

| 来源 | 处理 |
|------|------|
| 本地文件（md/pdf/doc） | Read |
| 截图 | Read 图片 |
| Figma | `mcp__figma__get_screenshot` + `get_metadata` |
| 长文本 | 直接作为输入 |

把所有素材合并为一份"待拆分原始材料"。

### Step 3 — 自动拆分

#### 3.1 拆分原则（四条）

1. **单一职责**：每个子需求只解决一个明确的业务目标，不混合无关功能。
2. **可测试性**：每个子需求要有可独立验收的标准；无法独立验收的合并或重新拆。
3. **依赖清晰**：识别子需求间的依赖（数据 / 接口 / UI 流程），避免循环依赖。
4. **大小均衡**：单个子需求工作量适中（小/中），过大则继续拆，过小则合并。

#### 3.2 依赖拓扑排序

- 识别每个子需求的**前置依赖**（哪些子需求必须先做）。
- 按拓扑顺序排序：被依赖者在前，依赖者在后。被依赖者编号小于依赖者。
- 存在循环依赖时：不输出排序结果，向用户反馈循环路径并请求拆解或调整。

#### 3.3 编号分配

- 起始编号 = `next_requirement_id`（来自 Preflight）。
- 按拓扑顺序从该编号起连续分配。
- **不**自己扫目录重算。

### Step 4 — 表格确认（**强制确认点**）

向用户输出待生成清单：

```
我准备拆成以下 N 个子需求，请确认：

| 编号 | 名称 | 优先级 | 工作量 | 前置依赖 | 一句话描述 |
|------|------|--------|--------|----------|-----------|
| <id1> | <name1> | <P1> | <小/中/大> | <无 / id> | <description> |
| <id2> | <name2> | ...    | ...    | ...      | ...        |
...

请回复：
  【1】确认，按上表生成
  【2】调整（请说明：合并 / 拆分 / 重排序 / 重命名 / 修改依赖 / 修改优先级）
  【3】取消
```

**硬约束**：

- 这是强制确认点。**禁止**在用户未明确选 1（或调整后再次确认）前进入 Step 5。
- 用户回"看起来不错 / 可以 / OK"等模糊表述时，必须再确认一次："请回复 1 / 2 / 3 之一"。

### Step 4.5 — 占位目录预创建（防并发编号冲突）

用户在 Step 4 选 1 后，**立即在 `<requirements_dir>` 下批量创建占位目录 + 写入标记文件 `_placeholder.md`**：

```
<requirements_dir>/<id1>-<name1>/_placeholder.md
<requirements_dir>/<id2>-<name2>/_placeholder.md
...
```

`_placeholder.md` 内容固定：

```markdown
# 占位 - 预留给 requirement-splitter 后续生成

> 本目录由 requirement-splitter Step 4.5 创建以保留编号块。
> 若 Step 5 批量生成失败或被中断，本目录将保留以备恢复。
> 若你确认不再需要本编号，可安全删除整个目录（编号会被下一次扫描重新分配）。
```

如此：
- 其他并发的 prd-writer / requirement-splitter 调用扫到这些目录后 `next_requirement_id` 会越过它们，避免编号重复。
- 其他主 skill（feasibility / fullstack / test）的 Preflight Step 3.0 扫到这些目录会识别 `_placeholder.md` 存在并标注 `[占位中]`，**不擅自继续**，提示用户"该目录尚未生成正式 `需求.md`，是否仍要继续？"。
- Step 5 成功后 `_placeholder.md` 自动删除（被 PRD.md / 需求.md 取代）；Step 5 失败时**不主动清理**，保留以备恢复（用户可手动删除整个目录）。

### Step 5 — 批量生成

按 Step 4 确认的清单，对每个子需求生成 `PRD.md` + `需求.md`（schema 严格按 `_shared/requirement-schema.md`）。

**所有模板的占位符遵循"`<尖括号>` 必换"规范，禁止使用圆括号中文注释作占位。**

PRD.md 简版骨架（拆分场景下允许简写，§4 方案设计等可只写要点）：

```markdown
# PRD - <编号> - <功能名>

> 来源：从 <原大 PRD 名称> 第 <N> 节拆分
> 产出日期：<YYYY-MM-DD>

## §1 背景
<简短>

## §2 目标
- <目标 1>

## §3 用户故事
- <角色>：<...>

## §4 方案设计（产品视角）
<要点列表，详情见原大 PRD>

## §5 非功能需求
<...>

## §6 验收标准
- AC-1 <...>

## §7 风险与未决问题
<...>

## §8 附录
- 父 PRD：<URL 或路径>
- 拓扑前置：<被依赖编号列表>
```

需求.md：完全按 `_shared/requirement-schema.md` 字段顺序与字段名，**不简写**。

### Step 5.1 — `_overview.md` 处理

- **本子 skill 不直接写 `_overview.md`**。批量生成完成后，向主 skill 返回结构化 `overview_update`（`action: bulk_init` + 全部 N 行）。
- 主 skill 收到后按其 Step C 处理：
  - 文件不存在 → 创建表头 + 写入 N 行。
  - 文件存在 → 提示用户三选一：
    ```
    <requirements_dir>/_overview.md 已存在。请选择：
      【1】覆盖（原表丢失）
      【2】合并（保留原行，新行追加；编号冲突时跳过新行并提示）
      【3】跳过（不写入 _overview.md）
    ```

### Step 5.2 — 完成回传

向主 skill 返回：

```yaml
result:
  status: ok | partial
  generated:
    - id: "<id1>"
      name: "<name1>"
      paths:
        prd: <requirements_dir>/<id1>-<name1>/PRD.md
        requirement: <requirements_dir>/<id1>-<name1>/需求.md
    - ...
overview_update:
  action: bulk_init
  rows:
    - id: "<id1>"
      name: "<name1>"
      status: "🔵 待开发"
      priority: "<P>"
      depends_on: "<...>"
      note: "—"
    - ...
notes:
  - <可选：跳过的子需求、模板冲突等>
```

## 产出规范

| 产物 | 路径 | 必填 |
|------|------|------|
| PRD.md（每个子需求） | `<requirements_dir>/<编号>-<功能名>/PRD.md` | 是（允许简写） |
| 需求.md（每个子需求） | `<requirements_dir>/<编号>-<功能名>/需求.md` | 是（不得简写，schema 严格） |
| `_overview.md` | 由主 skill 写入 | — |

## 失败处理

| 情况 | 处理 |
|------|------|
| Step 3 拆出 0 个独立子需求 | 报错回传"输入素材不足以拆分"，建议用户改走 prd-writer |
| Step 3 检测到循环依赖 | 输出循环路径，请用户调整拆分 |
| Step 4 用户回模糊表述 | 再次明确请求"1/2/3" |
| Step 4 用户取消 | 清理"思考中"内存状态，**不创建占位目录** |
| Step 5 部分生成失败 | 已成功的目录保留；report `status: partial` 列出失败编号与原因 |
| 编号撞车（极少见） | 重读 `next_requirement_id` 重算并提示用户 |

## 禁止事项

- **不省略任一子需求的 `需求.md`**：PRD 可简写，`需求.md` schema 必须完整。
- **不在未确认前批量创建文件**：Step 4 是强制确认点。
- **不照抄占位符本身**到产出文件中。
- **不直接写 `_overview.md`**，由主 skill 唯一负责写入。
- **不被顶层 skill 列表直接触发**。
- **不硬编码项目名 / 路径**。
- **编号顺序必须反映依赖方向**（被依赖者编号在前）。
- **不擅自修改用户在 Step 4 已确认的清单**；任何调整都需走"调整 → 再确认"循环。
