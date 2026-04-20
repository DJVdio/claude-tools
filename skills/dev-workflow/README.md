# 研发全流程 Skills

基于 [superpowers](https://github.com/anthropics/claude-plugins) 打通 **产品 → 全栈开发 → 测试** 的研发全流程。三个主 skill 通过自然语言关键词触发（也可用 Skill 工具直接调用），全程以**文件约定**而非进程内参数交接，所有产物按**需求编号**聚合到同一目录。

> **强制依赖 superpowers**：本套 skill 已从"可降级"改为"硬依赖"。Preflight 检测未装即硬 fail 并引导安装，**不再有降级 / 跳过 / 内联模拟模式**。

## 目标与适用场景

- **目标**：把一个子需求的 PRD / 可行性 / 实现 / 自审 / 改动总结 / 测试用例 / 自动化脚本 / 测试报告全部产出到同一目录，支撑"想清楚 → 做对 → 测稳"的节奏。
- **适用**：产品 + 研发 + 测试角色协作的项目；单人 AI-assisted 开发也适用（三个命令顺序跑）。
- **不适用**：纯脚本 / PoC / 不需要需求文档的一次性任务。

## 核心约束

1. **项目无关**：不硬编码项目名、路径、技术栈；运行时通过 `_shared/project-adapter.md` 自动探测，失败则 ask 用户。
2. **按需求编号聚合**：`<requirements-dir>/{编号}-{功能名}/` 内含该子需求全生命周期产物（9 类）。
3. **文件交接**：skill 之间不传参数，全部读 / 写约定文件。`需求.md` 与 `改动.md` 字段**严格结构化**（见 `_shared/requirement-schema.md`），下游可稳定解析。
4. **superpowers 强制依赖**：必须安装；未装时 Preflight 硬 fail 并输出引导话术。
5. **禁止硬编码**：skill 文件内一律使用 `<project-root>` / `<product-dir>` / `<requirements-dir>` / `<backend-dir>` / `<frontend-dir>` / `<test-dir>` / `<target-requirement-dir>` 等语义变量。
6. **会话级 diff 基线**：`fullstack-builder` 进入时记录 `session_base = git rev-parse HEAD`，全程 `git diff <session_base>`，不用 `git diff HEAD`（防止 commit 后 diff 变空导致 self-review 误放行）。

---

## 目录结构

```
.claude/skills/
├── README.md                            ← 本文件（入口）
├── config.example.yml                   ← 可选配置模板（复制为 config.yml 生效）
│
├── _shared/                             ← 跨 skill 共享 reference（被各 SKILL.md 引用）
│   ├── preflight.md                     ← 主 skill 启动三步检查（superpowers / 项目适配 / 输入就绪）
│   ├── project-adapter.md               ← 路径发现 / 技术栈识别 / 约定学习（Part 4 下游变量清单）
│   ├── file-conventions.md              ← 9 类产物命名、状态流转、覆盖策略
│   └── requirement-schema.md            ← 需求.md / 改动.md 的严格字段与解析规则
│
├── product-designer/                    ← /product 斜杠命令入口
│   ├── SKILL.md                         ← 编排器（分流到下列子 skill）
│   └── subskills/
│       ├── prd-writer/
│       │   └── SKILL.md                 ← 写新需求（PRD.md + 需求.md 双产出）
│       ├── requirement-splitter/
│       │   └── SKILL.md                 ← 拆大需求为多个子需求（_overview.md 由主 skill 统一写入）
│       └── feasibility-assessor/
│           └── SKILL.md                 ← 可行性评估（可行性.md）
│
├── fullstack-builder/                   ← /fullstack 斜杠命令入口
│   ├── SKILL.md                         ← 编排：plan → TDD → verification → self-review loop → change 总结
│   └── subskills/
│       ├── self-review/
│       │   └── SKILL.md                 ← 独立 subagent 六维度审查（自审报告.md 追加）
│       └── change-summarizer/
│           └── SKILL.md                 ← 产出 改动.md（对接 test-runner）
│
└── test-runner/                         ← /test 斜杠命令入口
    └── SKILL.md                         ← 测试用例（测试.md）+ 自动化脚本（automation/）+ 测试报告.md
```

---

## 三个主 skill

| 主 skill | 做什么 | 触发关键词（自然语言） | 直接调用 |
|---------|--------|----------------------|---------|
| `product-designer` | 写 PRD、拆大需求、评估可行性 | "写需求" / "新需求" / "加一个功能" / "新功能" / "拆需求" / "可行性" / "评估" | `Skill(skill="product-designer")` |
| `fullstack-builder` | 前后端一体开发 + 自审 loop + 改动总结 | "实现需求" / "开始开发" / "做这个子需求" / "前后端一起实现" / "落地 <编号>-<功能名>" | `Skill(skill="fullstack-builder")` |
| `test-runner` | 生成测试用例 + 接口自动化脚本 + 跑验证 | "生成测试用例" / "跑测试" / "做接口自动化" / "测试这个需求" | `Skill(skill="test-runner")` |

> **关于斜杠命令**：Claude Code 不会为本套 skill 自动注册 `/product` `/fullstack` `/test` 等顶层 slash command。skill 通过 frontmatter 的 `description` 关键词被自动识别，或用户用 `Skill` 工具直接调用主 skill 名字。子 skill（`prd-writer` / `requirement-splitter` / `feasibility-assessor` / `self-review` / `change-summarizer`）**仅由对应主 skill 内部派发**，不应被顶层直接触发；它们的 description 已加 "（内部子 skill）" 前缀以降低误触发概率。

### 典型链路

```
product-designer（prd-writer）       → PRD.md + 需求.md
product-designer（feasibility-assessor） → 可行性.md
fullstack-builder <编号>-<功能名>     → plan.md + 代码改动 + 自审报告.md + 改动.md
test-runner <编号>-<功能名>           → 测试.md + automation/ + 测试报告.md
```

---

## 产物约定（按需求编号聚合）

单个子需求的所有产物集中在 `<requirements-dir>/{编号}-{功能名}/` 内：

```
<requirements-dir>/
├── _overview.md                        ← 所有子需求总览（下划线前缀，避免与子需求目录混淆）
└── {编号}-{功能名}/
    ├── PRD.md                          (1) prd-writer —— 面向人阅读
    ├── 需求.md                         (2) prd-writer —— 面向 AI 严格 schema（FP-N / AC-N / 影响面提示）
    ├── 可行性.md                       (3) feasibility-assessor —— 结论 + 工作量 + 风险 + 文件清单
    ├── plan.md                         (4) fullstack-builder（superpowers:writing-plans 产出）
    ├── 自审报告.md                     (5) self-review —— 多轮追加（round-N）
    ├── 改动.md                         (6) change-summarizer —— 接口/DB/配置/影响面/前端交互点
    ├── 测试.md                         (7) test-runner —— 功能 / 接口 / 回归 / 前端手测清单
    ├── 测试报告.md                     (8) test-runner —— 多次运行追加（run-N）
    └── automation/                     (9) test-runner —— 独立可运行的接口自动化脚本
```

状态流转（见 `_overview.md`）：🔵 待开发 → 🟡 评估中 → 🟢 开发中 → 🟣 测试中 → ✅ 已完成

详细规则参见 [`_shared/file-conventions.md`](./_shared/file-conventions.md)。

---

## 与 superpowers 的关系

- **必须安装**：`/plugin install superpowers`。本套 skill 强制依赖 superpowers 提供的核心能力：
  - `superpowers:writing-plans` → 规划阶段产出 `plan.md`
  - `superpowers:test-driven-development` / `superpowers:executing-plans` → TDD 执行
  - `superpowers:verification-before-completion` → 完成前验证（测试 + 类型检查 + lint）
  - `superpowers:systematic-debugging` → 失败根因分析
  - `superpowers:requesting-code-review` / `code-review:code-review` → 可选协同
- **Preflight 硬依赖检测**：每个主 skill 启动第一步检测 `superpowers` 是否安装（多候选路径：`$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/` / `$USERPROFILE/.../` / `$CLAUDE_PLUGIN_DIR/superpowers/`）。未装即**硬 fail**，输出引导话术，**不再有降级模式**。
- **永不假装**：未装 superpowers 时**严禁**假装已调用 `superpowers:*`；Preflight 已硬 fail，主流程不会执行到调用点。

---

## 如何复制到其他项目

skill 设计为**项目无关**，整个 `.claude/skills/` 目录可原样复制到任何项目后直接工作。

### 步骤

1. **复制整个目录**：

   ```bash
   cp -r <source>/.claude/skills <target-project>/.claude/
   ```

2. **（可选但推荐）创建 `config.yml` 覆盖自动探测**：

   ```bash
   cd <target-project>/.claude/skills
   cp config.example.yml config.yml
   # 必须按实际项目编辑 paths / stack / options
   # 默认所有值都是 <auto-detect> 占位；如不修改保留占位即由 Preflight 自动探测；不要直接复制就用
   ```

   不建 `config.yml` 也能跑——首次运行任一主 skill 时 Preflight 会自动识别目录与技术栈；识别不全则交互询问，可选择写入 `config.yml` 持久化。

3. **首次运行即可**：

   ```
   触发 product-designer：写个需求：...
   ```

   Preflight 会：
   - **检测 superpowers 是否安装**（**必须装**，否则硬 fail）
   - 按 `_shared/project-adapter.md` 识别 `<product-dir>` / `<backend-dir>` / `<frontend-dir>` / `<test-dir>` / `<requirements-dir>`（含 monorepo 的 `apps/*` `packages/*`）
   - 识别后端栈（Java/Node/Python/Go/Rust/.NET/Ruby/PHP/Elixir/Scala/Deno/Bun）与前端栈（Vue/React/Next/Remix/Svelte/Angular/Solid/Qwik/Astro/Preact）
   - 识别测试栈（**允许与后端栈异构**，如 Node 后端 + pytest 测试目录）
   - 读 `CLAUDE.md` / `AGENTS.md` / `.cursorrules` 学习代码规范
   - 扫 2~3 个现有需求样例学习命名 / 模板风格

### 可移植性验证要点

- Grep 整个 `.claude/skills/` 不应出现特定项目名硬编码。
- 技术栈假设只出现在"识别分支"内，主流程不依赖特定栈。
- 路径表达全部使用 `<project-root>` / `<product-dir>` / `<backend-dir>` / `<frontend-dir>` / `<test-dir>` / `<requirements-dir>` / `<target-requirement-dir>` 语义变量。

---

## 跨项目兼容性

### 支持的栈枚举

完整枚举见 [`_shared/project-adapter.md`](./_shared/project-adapter.md) Part 4 与 [`config.example.yml`](./config.example.yml)。

| 类别 | 已支持 |
|------|--------|
| 后端 | Java(Maven/Gradle/Spring) / Kotlin / Node(Express/Koa/Fastify/Nest) / Python(FastAPI/Django/Flask) / Go(Gin/Echo/Fiber) / Rust(Actix/Axum/Rocket) / .NET(ASP.NET) / Ruby(Rails/Sinatra) / PHP(Laravel/Symfony/Slim) / Elixir(Phoenix) / Scala(Play/Akka) / Deno / Bun |
| 前端 | Vue / Nuxt / React / Next / Remix / Svelte / SvelteKit / Angular / Solid / Qwik / Astro / Preact |
| 后端测试 | JUnit5+RestAssured / Jest+Supertest / Vitest+Supertest / Mocha+Chai / pytest+httpx/requests/respx / go-test / cargo-test / xunit / nunit / rspec / phpunit / exunit / scalatest |
| 前端测试 | vitest / jest / karma+jasmine（可附加 testing-library） |

### 支持的目录布局

- 单仓常规：`backend/` `frontend/` `test/` `product/` 等
- monorepo：`apps/server` `apps/web` / `packages/api` `packages/web` / `services/*`
- 异构测试目录：后端 Node + 测试用 pytest（`qa/` 单独目录）
- 文档目录别名：`docs/` `prd/` `specs/` `design/` `product-docs/`（`prd/` 优先于 `docs/`）

### 已知局限

- **章节标题硬编码中文**：`需求.md` / `改动.md` 等 schema 章节标题为中文（`## 接口变更` / `### 新增` / `## 功能点` / ...），下游解析正则锚定中文。多语言版本尚未支持。
- **前端 UI 自动化不做**：Playwright / Cypress / Selenium 等明确不在范围内。
- **超大需求**：`feasibility-assessor` 限制 Read 5 个文件，超大复杂需求需先用 `requirement-splitter` 拆。

---

## Reference 文档

所有 skill 文件都会 Read 下列 `_shared/*.md` 作为权威引用。阅读顺序建议：

| 文档 | 用途 |
|------|------|
| [`_shared/preflight.md`](./_shared/preflight.md) | 主 skill 启动三步检查：superpowers 检测 / 项目适配 / 输入就绪 |
| [`_shared/project-adapter.md`](./_shared/project-adapter.md) | 路径发现三级优先级 / 技术栈识别表 / 约定学习 / Part 4 下游变量清单 |
| [`_shared/file-conventions.md`](./_shared/file-conventions.md) | 9 类产物命名 / `_overview.md` 状态流转 / 覆盖 vs 追加策略 |
| [`_shared/requirement-schema.md`](./_shared/requirement-schema.md) | `需求.md` / `改动.md` 字段严格定义与解析正则 |

---

## 范围外（本版本不做）

- 前端 UI 自动化（Playwright / Cypress）——当前以"前端手测清单"在 `测试.md` 中呈现
- 跨项目 skill 中心化管理——每个项目内独立维护
- 性能测试、压测
- 需求版本管理（v1 / v2 迭代）——当前是一次性产出
