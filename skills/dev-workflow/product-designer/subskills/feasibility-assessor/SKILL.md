---
name: feasibility-assessor
description: （内部子 skill，仅由 product-designer 主 skill 派发调用，不应被顶层直接触发）读指定子需求的 需求.md，中等深度扫描 backend/frontend 代码，产出 可行性.md（文件清单、改动类型、跨层分析、风险、工作量、结论），不写代码、不写方案
---

# Feasibility Assessor — 中等深度可行性评估

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 用户说"评估可行性 / 可做性 / feasibility"，并指定了一个目标子需求目录（或可从 `_overview.md` 推断）。
- 目标目录下**已存在** `需求.md`。

### 不适用场景

- `需求.md` 不存在 → 退回主 skill，让其走 `prd-writer` / `requirement-splitter` 先产出。
- 用户要求出代码、出架构方案、出 SQL → **拒绝**，本 skill 严禁越界。

### 自我保护：仅由主 skill 派发

本子 skill **不应**被 Claude Code 顶层关键词直接触发。若发现进入本 skill 时 **没有** 主 skill `product-designer` 已绑定的 Preflight 上下文，**立即拒绝执行**并提示：

```
本 skill 是 product-designer 的内部子 skill。
请先用 product-designer 入口（说"评估可行性 / 看看能不能做"等）触发，
让主 skill 完成 Preflight 后再进入本子 skill。
```

## 前置检查（Preflight）

主 skill 已完成 Preflight（见 `../../../_shared/preflight.md`）。本子 skill 使用已绑定变量：

- `project_root` / `backend_dir` / `frontend_dir`（任一为 `N/A` / `pending` 时按 `_shared/file-conventions.md` §8 短路规则跳过对应层）
- `backend_stack` / `frontend_stack`
- `code_conventions`
- `<target-requirement-dir>`（由 Preflight Step 3.0 已绑定）
- `superpowers_available`（必为 `true`）

额外检查：

1. `<target-requirement-dir>/需求.md` **必须**存在；否则阻断。
2. `需求.md` 中的字段顺序与 schema 一致（至少有 `## 功能点` 章节与 `### FP-N` 条目）；格式错误按 `_shared/requirement-schema.md` §3.2 ask 用户。

## 评估深度（中等）

**本 skill 的深度明确为"中等"**：

- 用 Grep **广度扫**：每个 FP-N 做定向搜索，覆盖 `<backend_dir>` / `<frontend_dir>`。
- 精选最相关文件做 Read 细读，**所有层合计硬上限**由 `config.yml` 的 `options.feasibility-read-max-files`（默认 **5**）控制；用户可调整。
- **不做**完整调用链追踪、不做运行时 profile、不写伪代码。

## 主流程

### Step 1 — 解析 `需求.md` 的功能点

- Read `<target-requirement-dir>/需求.md`。
- 按正则 `^### FP-(\d+)` 枚举功能点；对每个 FP 抽取"行为描述 / 输入 / 输出 / 异常"。
- 抽取"影响面提示（产品视角）"作为交叉验证线索。

### Step 2 — 代码库定位扫描（静态扫描 + 局限声明）

#### 2.0 N/A 短路

- `backend_stack = N/A`：跳过后端扫描，`涉及文件清单` 后端段写 `N/A（纯前端项目）`。
- `frontend_stack = N/A` / `pending`：跳过前端扫描，`前端交互点` 写 `N/A（纯后端 / 前端待建）`。
- 引用 `_shared/file-conventions.md` §8 N/A 栈短路规则。

#### 2.1 Grep 完成判定（可操作）

对每个 FP，按下列循环执行直到**完成判定满足**：

- 每轮选 1–2 个关键词做 Grep，命中位置记为该 FP 的"候选文件"。
- **完成判定（任一满足即停）**：
  1. **每个 FP 至少有 1 个候选文件**（可能找不到则进入"建议人工复核"，不再扩词）；
  2. **本子 skill 累计 Grep 次数达到 8 次硬上限**（避免漂变为方案设计）。

#### 2.2 候选文件 Read

从所有 FP 的候选合集里**精选最相关文件**做 Read。所有层合计硬上限按 `options.feasibility-read-max-files`（默认 **5**）；建议挑选区间 3–N（N 为该上限）。Read 完成即停。

#### 2.3 静态扫描的局限（必须在产出文档中声明）

- **动态加载组件**：例如 Vue/React 的 `import.meta.glob('./views/**/*.vue')`、异步路由、插件机制，Grep 可能找不到引用。
- **后端 DB 驱动菜单 / 权限**：菜单表、路由表、权限码在数据库里，静态 Grep 看不到；必须手动提示"需要查对应配置表 / 菜单 SQL"。
- **反射 / 字符串拼接调用**：Java 反射、Go `reflect`、Python `getattr`、Node 动态 require，静态搜索漏判。
- **跨服务 RPC / 消息**：只在 feign client / 消息主题常量里出现，需配合关键词二次检索。

本 skill **只声明局限**，不尝试绕过它们；把"建议人工复核位置"写进 `可行性.md`。

### Step 3 — 逐 FP 分类

对每个 FP 判定**改动类型**：

| 改动类型 | 定义 |
|----------|------|
| 新增 | 完全新的端到端能力（新 Controller/新页面/新表） |
| 修改 | 在已有代码基础上扩展或调整（已有接口加字段、已有页面加按钮） |
| 重构 | 已有功能的实现方式需要大范围调整（抽接口、拆模块、改分层） |

并判定**跨层范围**：

| 跨层 | 含义 | 工作量映射 |
|------|------|-----------|
| 单层 | 仅后端 或 仅前端 或 仅 DB | 小 |
| 跨层 | 后端 + 前端（或 + DB） | 中 |
| 跨服务 | 本服务 + 外部服务 / RPC / 消息契约 | 大 |

### Step 4 — 风险识别（要具体，不泛化）

每条风险至少包含三要素：**位置 + 问题 + 示例写法**。

格式示例（**仅作格式示范，不作为真实风险复用**）：

```
- 位置：<backend_dir>/<相对路径>:<行号>
  问题：<具体问题描述>
  示例写法：<触发问题的具体语句或表达式>
```

禁止："性能可能有问题"、"代码可维护性一般"这类泛化描述。

### Step 5 — 工作量估算

**只给定性等级，不给小时数**。

| 等级 | 典型特征 |
|------|---------|
| 小 | 单层 + 修改；< 3 个文件改动预期 |
| 中 | 跨层 + 修改/新增；3–10 个文件；无架构调整 |
| 大 | 跨服务 或 重构 或 涉及 DB schema 变更 或 依赖外部服务契约变更 |

**严禁**输出"预计 8 小时 / 2 人天 / 一周"等数字。

### Step 6 — 产出 `可行性.md`

路径：`<target-requirement-dir>/可行性.md`

> 模板中所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符。

```markdown
# 可行性 - <编号> - <功能名>

> 产出日期：<YYYY-MM-DD>
> 评估深度：中等（Grep ≤ 8 次 + Read ≤ 5 个文件）
> 评估者：feasibility-assessor（product-designer）

## 结论

- 可做性：<可做 | 有风险 | 需讨论>
- 工作量：<小 | 中 | 大>
- 建议下一步：<开发 | 先澄清 | 先做 spike>

## 功能点映射

| FP | 名称 | 改动类型 | 跨层 | 涉及层 |
|----|------|---------|------|--------|
| FP-1 | <名称> | <新增/修改/重构> | <单层/跨层/跨服务> | <backend / frontend / db / 跨服务> |
| FP-2 | <名称> | <...> | <...> | <...> |

## 涉及文件清单

（每条至少包含：路径 + 角色 + 为什么涉及；路径必须是相对 `<project_root>` 的相对路径）

- `<backend_dir>/<相对路径>` — <角色 / 为什么涉及>
- `<frontend_dir>/<相对路径>` — <角色 / 为什么涉及>

## 需改动的关键函数 / 组件

- `<类名.方法名>` — <扩展点 / 风险点>
- `<组件名>` — <暴露的事件 / 改造点>

## 推荐实现方向（**不是方案**）

- 方向 1：<一句话方向，不涉及具体代码>
- 方向 2：<一句话方向>

（**只写方向，不写代码 / SQL / 接口签名 / 详细实施步骤**）

## 技术风险

（每条三要素：位置 + 问题 + 示例写法）

- 位置：<...> 问题：<...> 示例写法：<...>

## 依赖冲突

- <外部服务 / 上下游接口 / 库版本 / 配置中心项>

## 静态扫描局限说明

（**必写章节**，不可省略）

- 已知本次评估的静态扫描**可能遗漏**下列位置，建议人工复核：
  - 动态加载组件：`import.meta.glob(...)` 生成的异步路由
  - DB 驱动的菜单 / 权限项（查 `<菜单表名 或 权限表名>` 等表）
  - 反射 / 字符串拼接调用点
  - 跨服务 RPC（如 feign client、消息主题常量）
- 建议人工复核位置（具体到文件或表）：
  - <文件 / 表 1>
  - <文件 / 表 2>
```

### Step 7 — 完成回传（**不直接写 `_overview.md`**）

- 写入 `可行性.md`。
- **不**直接修改 `<requirements_dir>/_overview.md`。
- 向主 skill 返回结构化数据，由主 skill 唯一负责写入 `_overview.md`：

```yaml
result:
  status: ok | partial
  paths:
    feasibility: <target-requirement-dir>/可行性.md
overview_update:
  action: update
  rows:
    - id: "<编号>"
      status: "🟡 评估中"
      note: "<可做性 / 工作量 / 建议下一步 简短结论>"
notes:
  - <可选：扫描局限提醒、需要用户后续澄清的点>
```

主 skill 收到后按其 Step C 处理。即使 `_overview.md` 不存在，由主 skill 创建表头并写入；本子 skill **不**自行回退到"提示用户手工补建"。

## 产出规范

| 产物 | 路径 | 必填 |
|------|------|------|
| 可行性.md | `<target-requirement-dir>/可行性.md` | 是（结构固定：结论 / 功能点映射 / 涉及文件 / 关键函数 / 推荐方向 / 风险 / 依赖冲突 / 静态扫描局限） |

覆盖策略：可行性.md 走"提示覆盖"。

## 失败处理

| 情况 | 处理 |
|------|------|
| `需求.md` 缺失或 FP 编号错乱 | 阻断，按 `_shared/requirement-schema.md` §3.2 ask 用户修正 |
| `backend_dir` 与 `frontend_dir` 都为 `N/A` / `pending` | 不应发生（纯文档项目不需要可行性），阻断并 ask 用户 |
| Grep 大量无关命中 | 压缩搜索词，结合 `backend_stack` / `frontend_stack` 收敛；仍无法收敛则在"静态扫描局限"章节说明并继续；命中超 8 次硬停 |
| 发现实际工作量远超"大"的上限 | 输出结论 `需讨论`，建议回 `requirement-splitter` 再拆 |
| 进入本 skill 时无主 skill 上下文 | 拒绝执行（自我保护节） |

## 禁止事项

- **严禁越界**：
  - 不写代码（任何语言的实现片段）
  - 不写详细实施步骤（"第 1 步改 A，第 2 步改 B"到行级粒度）
  - 不做架构决策（"应该用 CQRS / 引入 Redis Stream"之类）
  - 不写 SQL DDL / 具体接口签名
- **不给小时数 / 人天数**；工作量仅"小 / 中 / 大"。
- **不跳过"静态扫描局限说明"章节**。
- **不照抄占位符本身**到产出文件中。
- **不直接写 `_overview.md`**，由主 skill 唯一负责写入。
- **不被顶层 skill 列表直接触发**。
- **不硬编码项目名**；路径全部用语义变量（`<backend_dir>` 等）。
- **不把 "可能" 之外的风险写成确定结论**；未确认的风险应标注"推测"。
- **Grep 上限 8 次 + Read 上限按 `options.feasibility-read-max-files`（默认 5）**（合计），防止漂变为"方案设计"。
