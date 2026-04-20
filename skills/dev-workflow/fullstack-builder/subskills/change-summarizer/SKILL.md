---
name: change-summarizer
description: （内部子 skill，仅由 fullstack-builder 主 skill 通过 Read 调用，不应被顶层直接触发）fullstack-builder 的改动归档子 skill。在 self-review loop 通过后基于 git diff <session_base> + 需求.md + 代码产出 改动.md（严格按 requirement-schema §2 字段），面向 test-runner 作为唯一权威输入
---

# Change Summarizer — 改动归档

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 仅由 `fullstack-builder/SKILL.md` Step 6 进入（在 self-review loop 退出之后）。
- 代码改动已完成，`git diff <session_base>`（或 diff 范围）可取，`需求.md` 存在。

### 不适用场景

- 代码尚未改动（diff 为空）：无改动可归档，退回 `fullstack-builder`。
- `需求.md` 缺失或不可解析：`改动.md` 的 `功能点清单` 无法对齐 FP-N，**阻断**；回到上游。
- 用户让跳过 Step 6：按 `fullstack-builder/SKILL.md` §Step 6 的硬约束——**不得完全不产出**；至少产出按 schema 全字段填 `无` 的最小 `改动.md`。

## 前置检查（Preflight）

本子 skill 由 `fullstack-builder` 主会话 Read 后调用，不再重跑 `_shared/preflight.md`。进入前需确保以下上下文已由主 skill 提供或可直接读取：

1. `<target-requirement-dir>` 绝对路径 + `需求.md` 可读。
2. `session_base`（由 fullstack-builder Preflight Step 2.5 绑定）必须**已知**且**有效**。`git diff <session_base>` 可执行（在 `<project_root>` 下）。
3. Preflight 绑定的 `backend_stack` / `frontend_stack`（用于识别数据库迁移机制 / 配置中心 / 前端技术）。

**严禁退化为 `git diff HEAD`**：commit 之后 HEAD 等于已 commit 的状态，diff 会变空导致漏报；必须用 `session_base`（fullstack-builder 进入时记录的 base）。

**N/A 短路**：`frontend_stack = N/A` 时 `## 前端交互点` 章节直接写 `N/A（纯后端项目）`。`backend_stack = N/A` 时 `## 接口变更` 三节及 `## 数据库变更` / `## 配置变更` 写 `N/A（纯前端项目）`，但 `## 非 HTTP 契约` 仍按需填写。

## 主流程

### Step 1 — 读输入

1. **读 `需求.md`**：按 `../../../_shared/requirement-schema.md` §1.8 解析全部 FP-N（编号 + 名称 + 行为描述）、AC-N、影响面提示、头部元信息。
2. **取 diff**：执行 `git diff <session_base>`（`session_base` 由主 skill 传入，**必须**为有效 commit hash）。若 `session_base` 缺失或无效 → 回传错误"session_base 未绑定，无法取 diff"，不自行兜底。把 diff 拆成按文件分组的结构化数据：
   - 新增文件
   - 修改文件（含 hunks）
   - 删除文件 / 重命名
3. **取提交与分支信息**：`git rev-parse --abbrev-ref HEAD` 取分支；`git rev-parse HEAD` 取当前 commit；元信息行写 `<branch> @ <session_base>..<HEAD>（含/不含工作区）` 形式，明确"本次改动覆盖的范围"。
4. **读 `code_conventions`**（可选，影响错误码 / 鉴权措辞本地化）：不做强依赖。

### Step 2 — FP-N 对齐（功能点清单）

对需求中每个 FP-N 独立判定：

- 若 diff 中存在与该 FP 行为描述相关的代码（按关键字 / 路径 / 数据模型名定位），写 `- [x] FP-N 功能点名称：<一句话可测描述本次如何实现>`。
- 若未实现或仅部分实现，写 `- [ ] FP-N 功能点名称：未实现，原因：<简述>` / `- [ ] FP-N ...：部分实现，未实现项：<列出>`。

对每条 FP 都必须出现在清单中，**不得遗漏**。

### Step 3 — 接口变更（三小节齐全）

**硬性结构**：`## 接口变更` 下必须包含三个三级小节，顺序固定：`### 新增` → `### 修改` → `### 废弃`。任一小节为空写 `无`，**不得删除小节**。

#### 3.1 识别"新增 / 修改 / 废弃"

- **新增**：diff 中出现新的路由装饰器 / 注解（`@*Mapping` / `router.<method>` / `app.<method>` / `@RequestMapping` / `@GetMapping` / `@PostMapping` 等），或新增的 handler 函数绑定新路径。
- **修改**：路径不变但签名变（参数、body、响应 shape、鉴权、错误码）；或老接口行为变。
- **废弃**：被删除的路由、被标 `@Deprecated` 的接口、从路由表移除的条目；若项目有显式 deprecation 机制（注解 / 注释约定）也算入。

#### 3.2 每条接口必填字段

按 `_shared/requirement-schema.md` §2.4：

**新增**：
- `用途`
- `请求`（body / query / headers / path params；每项含字段名 + 类型 + 是否必填）
- `响应`（data 结构 / 成功响应体）
- `错误码`
- `鉴权`

**修改**：
- `变更前` / `变更后`
- `兼容性`（向后兼容 / 破坏性；破坏性须写迁移方案）

**废弃**：
- `废弃原因`
- `替代方案`
- `预计下线版本`

任一子字段缺信息写 `无`，不得省略。

#### 3.3 接口标识格式

每条接口首行：`- **\`POST /api/xxx\`**`（粗体 + inline code），方法大写，路径以 `/` 开头，path variable 保持原样（`{id}` / `:id` 以代码实际为准）。

### Step 4 — 数据库变更

**自适应识别机制**（**本 skill 不假设项目用哪种**，按文件名特征命中，详细识别表见 `_shared/project-adapter.md` §"数据库迁移识别"）：

- **flyway**：文件名符合 `V\d+__.*\.sql` / `R__.*\.sql`（任何路径，不绑定 `src/main/resources/db/migration/` Java/Maven 布局）。
- **liquibase**：`\d+_.*\.sql` + `changelog.xml` / `.yml` 同级。
- **knex / sequelize-cli / typeorm**：`migrations/` 目录 + JS/TS 文件含 `up` / `down` exports。
- **prisma**：`prisma/migrations/` + `migration.sql`。
- **drizzle-kit**：`drizzle/` 目录 + `meta/_journal.json`。
- **手写 SQL**：列出所有 `*.sql` 文件 + 备注"未识别到迁移机制，建议补"。
- **ORM AutoMigrate**（Django / Alembic / GORM 等）：按 ORM 工具产物识别。

按命中机制列出本次新增的迁移文件与变更摘要。

条目粒度：
- 表新增 / 表删除 / 表重命名
- 字段新增 / 字段修改（类型 / 长度 / 默认值 / 注释 / 可空）/ 字段删除
- 索引新增 / 索引删除 / 索引修改
- 约束（外键 / 唯一键 / CHECK）

无数据库变更写 `无`。

### Step 5 — 配置变更

- 新增 / 修改 / 删除配置项（`application*.yml` / `application*.properties` / `.env` / `config/*.ts` / `application.yaml` 覆盖项 / Nacos 配置键 / Consul 键 等）。
- 每条含：key、默认值、作用、**是否需部署时同步配置中心**（Nacos / Consul / Apollo / env 文件）。
- 若用户项目未使用配置中心，"同步配置中心"字段写 `N/A`。
- 无配置变更写 `无`。

### Step 6 — 影响面

- 把 `需求.md` 的 "影响面提示（产品视角）" 作为起点，交叉验证 diff 中**公共符号**的调用方（被改动的 public class / exported function / 公共 route / 公共 SQL mapper）。
- 每条格式："功能名称 + 受影响原因 + 回归建议"。
- 大部分改动都有影响面；确实无影响才写 `无`，并附一句理由。

### Step 6.5 — 非 HTTP 契约（事件 / 定时 / 消息 / 邮件）

适用于 `## 接口变更` 三节全为 `无` 但项目代码中检测到非 HTTP 改动的场景（典型：定时任务、事件驱动、消息监听、邮件发送）。

按 `_shared/requirement-schema.md` §2.4b 的字段规范填写四个三级小节：

- `### 定时任务变更`：检测 `@Scheduled` / `node-cron` / `xxl-job` / `apscheduler` 等。
- `### 事件监听变更`：检测 `@EventListener` / `ApplicationEventPublisher` / `EventEmitter` / Bus 模式。
- `### 消息通道变更`：检测 RabbitMQ / Kafka / Redis Stream / SQS / NATS 的生产者 / 消费者代码。
- `### 邮件/通知通道变更`：检测 `JavaMailSender` / `nodemailer` / 通知 SDK 调用。

无对应类别时写 `无`，**不得删除小节**。

**特殊提醒**：当 `## 接口变更` 三节全为 `无`，且 `## 非 HTTP 契约` 四节也全为 `无` → 警告"本需求无任何外部可观测变更，是否纯内部重构？"，请用户确认后再落盘。

### Step 7 — 前端交互点

- 变更涉及的前端页面 / 组件 / 状态管理 / 路由。
- 每条**三要素齐全**：
  1. **页面或组件**（路径 + 名称）
  2. **用户操作路径**（从哪个入口进 → 做什么操作 → 触发哪个接口 / 哪个视图变化）
  3. **手测关注点**（校验 / 边界 / 错误态 / 鉴权态 / 空态 / 加载态）
- 纯后端变更无前端影响：写 `无`（或 `N/A`）。

### Step 8 — 头部元信息与落盘

文件路径：`<target-requirement-dir>/改动.md`。

**文件头必须含**：

```markdown
# 改动 - {编号} - {功能名}

> 对应需求：{编号}-{功能名}
> 产出日期：YYYY-MM-DD
> 对应 commit/分支：<branch> @ <session_base>..<HEAD>（工作区未提交时写"工作区未提交（基于 <session_base 前 7 位>）"，其中 session_base 由 fullstack-builder Preflight Step 2.5 绑定）
```

三行元信息**全部必填**，缺一不可。

覆盖策略：已存在则按 `../../../_shared/file-conventions.md` §5 的"提示覆盖"交互模板处理（覆盖 / 备份后覆盖 / 取消）。

## 产出规范（完整模板）

**字段顺序严格按 `_shared/requirement-schema.md` §2.1，不得乱序，不得删节，缺失写 `无` / `N/A`**：

```markdown
# 改动 - {编号} - {功能名}

> 对应需求：{编号}-{功能名}
> 产出日期：YYYY-MM-DD
> 对应 commit/分支：...

## 功能点清单
- [x] FP-1 ...：...
- [ ] FP-2 ...：未实现，原因：...

## 接口变更
### 新增
- **`POST /api/...`**
  - 用途：<...>
  - 请求：<...>
  - 响应：<...>
  - 错误码：<...>
  - 鉴权：<...>

### 修改
- **`GET /api/...`**
  - 变更前：<...>
  - 变更后：<...>
  - 兼容性：<...>

### 废弃
- 无

## 非 HTTP 契约
### 定时任务变更
- **`<任务标识>`**
  - 触发表达式：<...>
  - 触发条件：<...>
  - 业务动作：<...>
  - 实现位置：<...>

### 事件监听变更
- 无

### 消息通道变更
- 无

### 邮件/通知通道变更
- 无

## 数据库变更

- <表/字段/索引/迁移文件 列表项；本节确实无变更时写 `- 无`>

## 配置变更

- <配置项 key + 默认值 + 作用 + 是否同步配置中心；无变更时写 `- 无`>

## 影响面

- <功能名称 + 受影响原因 + 回归建议；无影响时写 `- 无`>

## 前端交互点

- <页面/组件路径 + 用户操作路径 + 手测关注点；纯后端项目写 `- N/A（纯后端改动）`>
```

## 失败处理

| 情况 | 处理 |
|------|------|
| `git diff <session_base>` 为空 | 不落盘 `改动.md`；回报主 skill"无改动"，由主 skill 决定是否跳过 Step 6 或重入 Step 3 |
| `需求.md` FP 解析失败（格式不符 schema） | 阻断，按 `_shared/requirement-schema.md` §3.2 让主 skill 回上游修 |
| 某字段真无法确定（如废弃接口的"预计下线版本"） | 写 `无`，**不省略**；避免写"待定"这类半值 |
| 数据库迁移机制无法识别 | 按 Step 4 兜底分支，写"未发现迁移脚本"；不假设机制 |
| 前端技术栈为 N/A（纯后端项目） | `## 前端交互点` 写 `N/A` |
| `改动.md` 已存在 | 按 `_shared/file-conventions.md` §5.1 提示覆盖模板 |

## 禁止事项

- **不主观评价代码质量**：本 skill 只做"客观归档"，不写"这里写得不好 / 这段实现不优雅"；代码质量问题是 `self-review` 的职责。
- **不得删除 schema 规定的章节或小节**（`### 新增` / `### 修改` / `### 废弃` 三节必须齐全，空写 `无`）。
- **不得乱序章节**：顺序必须严格按 `_shared/requirement-schema.md` §2.1。
- **不得省略字段**：缺失必须写 `无` / `N/A`，不得留空或删除条目项。
- **不得遗漏 FP-N**：`需求.md` 的每个 FP-N 必须在"功能点清单"中出现，即便未实现也要 `- [ ]` 标并写原因。
- **不假设数据库迁移机制**：不得硬编码"本项目用 flyway / liquibase"；按 Step 4 的识别分支逐一检测。
- **不假设项目用哪个配置中心**：按 Step 5 的识别分支检测；未用配置中心写 `N/A`。
- **不主动 git commit**：本 skill 只读 diff、写 `改动.md`；不执行 `git add` / `git commit` / `git push`。
- **不硬编码项目名 / 路径 / 技术栈**：全部引用 `<project_root>` / `<target-requirement-dir>` / `<backend_dir>` / `<frontend_dir>` 等语义变量。
- **不覆写已有 `改动.md` 而不走提示覆盖**：按 `_shared/file-conventions.md` §5.1 三选一（覆盖 / 备份后覆盖 / 取消）。
