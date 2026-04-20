# Preflight — 主 skill 启动前置检查

> **定位**：reference 文档，非 skill。所有主 skill（`product-designer` / `fullstack-builder` / `test-runner`）在进入主流程前必须完成本文件定义的检查。
>
> **读取方式**：主 skill 用 Read 工具加载本文件后，按顺序执行 Step 1 → Step 2 → Step 2.5 → Step 3.0 → Step 3。

---

## 总览

| 步骤 | 目的 | 依赖 | 产出 / 绑定 |
|------|------|------|------|
| Step 1 | superpowers 安装检测（**硬依赖**） | 无 | 未装 → 硬 fail + 引导安装；装好 → 继续 |
| Step 2 | 项目适配（路径/技术栈/约定） | 详见 [`./project-adapter.md`](./project-adapter.md) | 绑定所有下游上下文变量 |
| Step 2.5 | 记录 `session_base` | Step 2 已进入仓库 | 绑定 `session_base = git rev-parse HEAD`，作为 /fullstack 全程 diff 基线 |
| Step 3.0 | `<target-requirement-dir>` 推断 | Step 2 | 绑定 `<target-requirement-dir>` |
| Step 3 | 输入就绪检查（按当前主 skill） | Step 2 / 3.0 产出 | 决定是否可进入主流程 |

---

## Step 1 — superpowers 硬依赖检测

> **硬约束**：本套 skill 已从"可降级"改为"**强制依赖 superpowers**"。检测未通过即硬 fail，**禁止进入 Step 2 及之后任何步骤**。

### 1.1 检测时机

**每次主 skill 被触发时都执行**（读 config.yml 与 `ls` 探测成本极低，不做 session 缓存，避免"已做过一次"的模糊判断引发漏检）。

### 1.2 检测路径

使用 Bash（`ls`）或等价能力探测下列候选绝对路径中至少一个存在：

```
$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/
$USERPROFILE/.claude/plugins/cache/claude-plugins-official/superpowers/
$CLAUDE_PLUGIN_DIR/superpowers/
```

展开后形如：`/Users/<user>/.claude/plugins/cache/claude-plugins-official/superpowers/`。

作为辅助判定：若当前 runtime 能在可用 skill 列表中看到 `superpowers:writing-plans` / `superpowers:test-driven-development` / `superpowers:verification-before-completion`，也视为已安装。

### 1.3 判定

- 任一候选路径存在，或 runtime 暴露 `superpowers:*` skill → 绑定 `superpowers_available = true`，Step 1 结束，进入 Step 2。
- 全部候选均不存在且 runtime 未暴露 `superpowers:*` skill → 绑定 `superpowers_available = false`，**立即硬 fail**，输出 1.4 的引导话术，**终止当前 skill 执行**，不进入 Step 2。

### 1.4 硬 fail 引导话术（未安装时必出）

向用户展示以下提示后**终止本 skill**，等待用户安装后重新触发：

```
本套 skill 强制依赖 superpowers 插件（writing-plans /
test-driven-development / verification-before-completion
等核心能力的提供方），检测未通过，已中止执行。

请按以下步骤操作后重新触发本 skill：

  1. 在 Claude Code 中执行：/plugin install superpowers
  2. 确认以下任一路径已存在：
     - $HOME/.claude/plugins/cache/claude-plugins-official/superpowers/
     - $CLAUDE_PLUGIN_DIR/superpowers/
  3. 重新向我发送原指令（如 /fullstack-builder ...）

本 skill 不再提供"降级 / 跳过 / 内联模拟"模式；
如有特殊需求请明确提出并确认放弃相应质量保障。
```

---

## Step 2 — 项目适配

> **本步骤不在本文件展开**。路径发现、技术栈识别、项目约定学习、下游上下文变量定义，全部见 [`./project-adapter.md`](./project-adapter.md)。

主 skill 在此处 Read [`./project-adapter.md`](./project-adapter.md) 并按其 Part 1 ~ Part 4 执行：

1. Part 1 — 路径发现（config.yml → 常见命名 → ask）
2. Part 2 — 技术栈识别（后端/前端标志文件映射 + 测试栈独立识别）
3. Part 3 — 项目约定学习（CLAUDE.md / AGENTS.md / 需求模板样例 / 编号规则）
4. Part 4 — 绑定下游变量集合

Step 2 结束后，下游步骤可直接使用 Part 4 定义的所有变量，**preflight 本文件不重复任何路径或栈判断逻辑**。

---

## Step 2.5 — 记录 session_base（diff 基线）

进入 /fullstack-builder 等会修改代码的主 skill 时，**立即**绑定：

```
session_base = git rev-parse HEAD
```

说明：

- `session_base` 是本次 skill 会话开始时的 HEAD commit hash，贯穿后续所有轮次的 self-review / change-summarizer。
- 下游 `self-review` / `change-summarizer` 等步骤**必须**使用 `git diff <session_base>`，**不得使用** `git diff HEAD`（否则只能看到未提交变更，漏掉本会话中已 commit 的内容）。
- 若 `git rev-parse HEAD` 失败（如不在 git 仓库或处于初始空仓库），绑定 `session_base = <empty>`，下游用 `git diff --no-index /dev/null <file>` 或枚举新文件兜底，并向用户说明。
- 本步骤对 `product-designer` / `test-runner` 仍然执行（保持接口一致；两者一般不改代码，但记录 base 不会造成副作用）。

---

## Step 3.0 — `<target-requirement-dir>` 推断算法（硬约束）

绑定变量 `<target-requirement-dir>`（形如 `<requirements_dir>/{编号}-{功能名}/`）。对除"纯新建需求"外的所有入口都**必须**执行本步骤。

### 3.0.1 推断算法

1. **用户消息正则匹配**：在用户当次消息（含附带 slash 参数）中用正则 `(\d+)-([\u4e00-\u9fa5a-zA-Z0-9_-]+)` 扫描，取首个命中：
   - 若命中，拼 `<requirements_dir>/<编号>-<名称>/`，校验目录存在：
     - 存在 → 绑定并结束。
     - 不存在 → 进入步骤 2（不直接 ask，避免漏看同编号不同命名）。
2. **列目录让用户选**：扫 `<requirements_dir>/` 下所有**不以下划线开头**、形如 `(\d+)-...` 的子目录，列表展示（含编号、功能名、状态——从 `_overview.md` 读；读不到则仅列目录名），请用户选择一个编号。
   - **占位过滤**：若该子目录下存在 `_placeholder.md` 文件（由 `requirement-splitter` Step 4.5 创建），在列表中显式标注 `[占位中：尚未生成 需求.md]`；用户硬选时必须先提示"该目录尚未生成正式 `需求.md`，是否仍要继续？（强烈不建议；请先让 requirement-splitter Step 5 完成生成）"，用户明确确认后才放行。
3. **仍无法确定则 ask**：`<requirements_dir>` 为空或用户未选时，进入 ask：

   ```
   未能确定 <target-requirement-dir>。
   请回复一个已存在的子需求编号（或目录名），
   或先运行 /product-designer 新建需求。
   ```

### 3.0.2 例外

- 入口为 `prd-writer`（新建需求）或 `requirement-splitter`（从大 PRD 拆分，目标目录尚未生成）时，Step 3.0 可以跳过；此时由对应子 skill 负责生成目录后再回写。
- 入口为 `feasibility-assessor` / `fullstack-builder` / `test-runner` 时，**禁止跳过** Step 3.0。

---

## Step 3 — 输入就绪检查

按当前主 skill 的身份，选择对应的判定分支。**`frontend_stack = N/A` 时跳过所有前端相关就绪判定。**

### 3.1 当主 skill 是 `product-designer`

- **必要条件**：
  - Step 2 已绑定 `product_dir`、`requirements_dir`。
- **子分流判定输入**：
  - 用户输入中含"写需求 / 新需求 / PRD / 写 PRD" → 进入 `prd-writer` 子 skill；不需要任何已存在的需求文件。
  - 用户输入中含"拆需求 / 分解 / 拆分 / split" + 上传大 PRD 或已有 PRD.md 路径 → 进入 `requirement-splitter`；需要能读到原始大需求的源头（口述 / 截图 / 文件）。
  - 用户输入中含"可行性 / 评估 / feasibility" → 进入 `feasibility-assessor`；**必须**已由 Step 3.0 绑定 `<target-requirement-dir>`，且该目录下存在 `需求.md`。
- **不满足时**：
  - 新需求类无需预置文件，放行。
  - 可行性评估类若 `<target-requirement-dir>` 或 `需求.md` 不存在 → **不得进入主流程**，ask 用户补充或先走 `prd-writer`。

### 3.2 当主 skill 是 `fullstack-builder`

- **必要条件**：
  - Step 2 已绑定 `requirements_dir`、`backend_stack`（或 `N/A`）、`frontend_stack`（或 `N/A`）。
  - Step 3.0 已绑定 `<target-requirement-dir>`。
  - 至少 `backend_stack` 与 `frontend_stack` 之一非 `N/A`（全 `N/A` 无法进入开发）。
- **强制存在**：
  - `<target-requirement-dir>/需求.md`
- **推荐存在**：
  - `<target-requirement-dir>/可行性.md`（缺失时警告但不阻断；询问用户是否先跑 `feasibility-assessor`）。
- **纯后端短路**：
  - `frontend_stack = N/A` → 跳过所有前端相关就绪判定（如前端目录存在性、`frontend_dir/package.json` 读取等）。
- **不满足时**：
  - `需求.md` 缺失 → 阻断，ask 用户先走 `product-designer` / `prd-writer`。
  - 多个待开发需求可选时，由 Step 3.0 的算法处理，不在此处重复。

### 3.3 当主 skill 是 `test-runner`

- **必要条件**：
  - Step 2 已绑定 `test_dir`、`test_backend_stack`、`test_frontend_stack`（未识别则 ask；`N/A` 合法）。
  - Step 3.0 已绑定 `<target-requirement-dir>`。
- **强制存在**：
  - `<target-requirement-dir>/改动.md`
- **推荐存在**：
  - `<target-requirement-dir>/需求.md`（用于对照 FP-N 覆盖度）。
- **纯后端短路**：
  - `frontend_stack = N/A` → 跳过所有前端测试就绪判定，`test_frontend_stack` 视为 `N/A`。
- **不满足时**：
  - `改动.md` 缺失 → 阻断，提示用户先完成 `fullstack-builder` 产出的 `change-summarizer` 环节。
  - 状态未推进到 🟣 测试中 / 🟢 开发中 → 警告但允许用户确认后继续。

---

## 禁止事项

- **不得跳过 Preflight**：任何主 skill 启动后，必须完整执行 Step 1 → Step 2 → Step 2.5 → Step 3.0 → Step 3，不得以"已经做过一次"为由跳过；**每次主 skill 被触发都执行**。
- **不得伪装 superpowers 已装**：未装即硬 fail，不得进入 Step 2；不得自行内联模拟 `superpowers:writing-plans` / `superpowers:test-driven-development` / `superpowers:verification-before-completion` 等能力。
- **不得把路径/栈判断逻辑写在本文件**：所有此类逻辑只在 [`./project-adapter.md`](./project-adapter.md) 维护，本文件只做"指引 + 流程"。
- **不得跳过 Step 3.0 的目录推断**（除 3.0.2 明确例外外）。
- **Step 3 判定失败时不得默默构造空目录或占位文件**：必须 ask 用户或回退到前置 skill。
- **下游 diff 基线必须用 `session_base`**，不得使用 `git diff HEAD`。
