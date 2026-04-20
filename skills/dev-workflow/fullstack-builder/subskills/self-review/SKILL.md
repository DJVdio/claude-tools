---
name: self-review
description: （内部子 skill，仅由 fullstack-builder 主 skill 通过 Agent 工具派发，不应被顶层直接触发）fullstack-builder 的独立自审子 skill。必须由 Agent 工具派发独立 subagent 执行（主会话禁止直接跑），按六维度（需求覆盖/契约一致性/代码规范/影响面/单元测试/本轮增量）审查开发产物，追加 Round-N 到 自审报告.md
---

# Self Review — 独立 subagent 自审

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 仅由 `fullstack-builder/SKILL.md` Step 5 通过 **Agent 工具派发**子 agent 时进入。
- 一个开发周期内可能进入多轮（Round 1 / Round 2 / ...），每轮由上层 loop 决定。

### 不适用场景

- 用户直接在主会话说"帮我做 self-review"：**拒绝**。必须由 `fullstack-builder` 主 skill 以 Agent 派发方式触发，以避免"自己审自己"的确认偏误。
- 需求文档本身还没定稿 / `需求.md` 缺失 / 没有任何代码改动：无从审查，退回 `fullstack-builder` 处理。

## 执行者约定（硬约束）

- **主会话不得直接执行本 skill**。若发现进入本 skill 时不是来自 Agent 工具派发（例如用户直接说"做 self-review"），**立即拒绝执行**并指引用户走 `fullstack-builder` 入口。
- **必须由 `fullstack-builder` 主 skill 使用 Agent 工具派发 general-purpose 或 code-reviewer 类 subagent**，由该 subagent Read 本 SKILL.md 并按其主流程执行。
- 派发时传入的 **7 字段最小上下文**（由 `fullstack-builder/SKILL.md` §5.1 规定）：
  1. `target_requirement_dir` 绝对路径
  2. `session_base` git base commit hash（**全程 diff 基线；下游所有 diff 都用 `git diff <session_base>`，严禁退化为 `git diff HEAD`**）
  3. `round_n` 本轮编号（1, 2, 3, ...）
  4. `code_conventions` Preflight 绑定的代码规范全文
  5. `superpowers_available`（必为 `true`）
  6. `backend_dir`（或 `N/A`）
  7. `frontend_dir`（或 `N/A`）

  缺任一字段 → 报错回传"上下文不足：缺 X"，**不擅自构造**。

## 前置检查（Preflight）

本子 skill 由 Agent 派发进入，不再重跑 `_shared/preflight.md`。但 subagent 在开始前**必须**校验：

1. 上述 7 字段派发上下文是否齐全；任何一项缺失 → 报错回传"上下文不足：缺 X"，不擅自构造。
2. `<target_requirement_dir>/需求.md` 可读；解析不到 FP-N 列表 → 报错回传。
3. `git diff <session_base>` 可执行；否则报错回传"无法获取改动范围（session_base 未绑定或无效）"。**严禁退化为 `git diff HEAD`**（commit 之后 HEAD 等于已 commit 状态，diff 会变空导致漏审）。

## 主流程（六个审查维度）

按编号依次执行；每个维度独立得出结论后汇入本轮报告。

### 维度 1 — 需求覆盖

**目标**：对照 `需求.md` 的每个 FP-N / AC-N，判断代码实现是否覆盖。

执行细节：
1. 解析 `需求.md`：按 `_shared/requirement-schema.md` §1.8 正则 `^### FP-(\d+)` 抽所有 FP；按 `AC-(\d+)` 抽所有 AC。
2. 对每个 FP-N：
   - 在 diff 范围内 grep 相关关键字（行为描述、接口路径、数据模型名）。
   - 判定：**已覆盖 / 部分覆盖 / 未覆盖 / 无法判定**（后三者必须进入问题清单）。
3. 对每个 AC-N：比对是否有对应测试用例 / 可运行的断言存在（维度 5 会交叉校验）。

### 维度 2 — 契约一致性（HTTP + 非 HTTP）

**目标**：前后端 / 内部组件间的契约**逐字段 / 逐 key**对得上。

#### 2a HTTP 契约（前后端调用一致性）

`frontend_dir = N/A` 时本子项跳过（按 `_shared/file-conventions.md` §8 N/A 短路）。

**具体比对步骤**（每个接口都走完）：

1. **路径**：前端调用串（如 `axios.post('/api/xxx/yyy')` / `fetch('/api/...')`) vs 后端路由定义（`@RequestMapping` / `@PostMapping` / `router.post` / `app.get`）。大小写、斜杠末尾、path variable 占位（`{id}` vs `:id`）必须一致。
2. **方法**：GET / POST / PUT / PATCH / DELETE 是否一致。
3. **参数名大小写**：camelCase vs snake_case vs kebab-case；前端发送字段名 vs 后端接收字段名必须完全一致（包括大小写）。
4. **类型**：前端 TS 类型（或解构使用处推断）vs 后端 DTO / entity 字段类型；数字 vs 字符串 vs 布尔、可空性。
5. **必填性**：前端是否必传 vs 后端 `@NotNull` / `required: true` / validator 规则；缺失时后端行为是否符合前端预期。
6. **响应字段**：后端返回结构（DTO / VO / JSON shape）vs 前端解析使用路径（`res.data.xxx.yyy`）；字段命名、嵌套层级、数组 vs 对象、空值语义（`null` vs 不存在）必须一致。
7. **错误码 / 状态码**：前端对 4xx / 5xx / 业务错误码的分支处理 vs 后端实际抛出；无需完全枚举但重点路径必须对齐。
8. **鉴权**：前端是否带 token / cookie vs 后端是否需要（`@PreAuthorize` / 中间件 / 守卫）；匿名接口是否真的放开。

#### 2b 内部契约（非 HTTP：定时 / 事件 / 消息 / 邮件）

适用于：纯后端需求 / 异步驱动需求（HTTP 接口三节为 `无` 但有非 HTTP 改动）。

**具体比对步骤**：

1. **定时任务一致性**：
   - 触发表达式（cron / fixed-delay / 触发器名）与"产品需求中"的触发条件是否一致（如 `需求.md` 写"赛季结束 30 分钟后"而代码用 `0 0 0 * * ?` → 不一致）。
   - Scheduled Bean 的处理逻辑是否覆盖 FP-N 的"业务动作"。
2. **事件契约**：
   - 事件类 / event name 在发布者与监听者两端**完全一致**（拼写、大小写、版本）。
   - 事件载荷字段在发布点构造 vs 监听器使用路径必须对齐。
3. **消息通道契约**：
   - MQ topic / exchange / routing key 在生产者与消费者两端字符串完全一致。
   - 消息体序列化字段（生产时 set 哪些 vs 消费时 get 哪些）必须对齐。
   - 顺序性 / 幂等性约束是否被消费方实现。
4. **邮件 / 通知 channel**：
   - 模板 key 在发送方调用 vs 模板存储位置 vs 收件人规则三处一致。
   - 渲染所需变量是否在发送方传入。

每条不一致必须进入问题清单（P0 或 P1）。

### 维度 3 — 代码规范

**事实来源**：派发上下文传入的 `code_conventions`（即 Preflight 聚合的 `CLAUDE.md` / `AGENTS.md` / `.cursorrules` / 子目录 CLAUDE.md 内容）。

**执行规则**：
- **本维度规则从 `code_conventions` 读，不硬编码任何具体项目规则**。以下任何具体规则若写出来，**必须同时标注"示例不硬编码"**，实际执行仍以 `code_conventions` 为准：
  - **示例不硬编码**：如 `code_conventions` 规定"所有文档和注释使用中文"，则审查注释语言；`code_conventions` 未规定则跳过该子项。
  - **示例不硬编码**：如 `code_conventions` 规定"Git 提交信息使用中文"，则审查 commit message；`code_conventions` 未规定则跳过。
  - **示例不硬编码**：如 `code_conventions` 规定"分支为 master"，则审查分支命名；`code_conventions` 未规定则跳过。
- 如果 `code_conventions` 为空（纯新项目无任何规约文件），该维度结论写"无规约可比，跳过"。

**比对面**：
- 命名（类 / 方法 / 变量 / 常量 / 文件）
- 目录结构 / 分层
- 异常处理 / 日志风格
- 注释语言与密度
- 代码提交信息格式（若规约涉及）

每条违规进入问题清单（一般 P1）。

### 维度 4 — 影响面

**目标**：改动是否对未列入需求的现有功能造成回归风险。

执行细节：
1. 从 diff 中抽出所有被改动的**公共符号**（public class / 导出的 function / 公共接口 / 公共 route）。
2. 对每个符号在整个代码库 grep 调用方；新增被调用位置或隐含行为变化时必须进入问题清单。
3. 交叉验证 `需求.md` 的 "影响面提示" 章节：产品提示的回归点是否都在本次 diff 中体现了"评估痕迹"（改了 / 明确未改并写理由）。

### 维度 5 — 单元测试

**目标**：测试覆盖度与边界条件。

执行细节：
1. 对每个 FP-N / AC-N：
   - 是否存在至少 1 条正向测试？
   - 是否存在至少 1 条异常 / 边界测试？
2. 对每个新增 / 修改的公共方法：是否有对应的单测？
3. 覆盖缺失或边界缺失 → 进入问题清单。

### 维度 6 — 本轮增量（仅 Round N ≥ 2 时）

**目标**：对比上一轮 `自审报告.md` 的问题清单，判定本轮修复情况，避免 loop 变"走过场"。

执行细节：
1. Read 上一轮 `自审报告.md`，抽取其 Round (N-1) 的问题清单。
2. 对**每一条**上一轮问题，给出状态标签（四选一，必须明确）：
   - **已修复**：diff 中能看到对应修复代码，且问题不再存在。
   - **部分修复**：仅修了一部分（说明哪部分未改 / 哪部分已改）。
   - **未修复**：问题仍然存在。
   - **新引入**：本轮修改引入了新的相关问题（同类 / 同文件）。
3. 额外识别"本轮新增问题"（上一轮未出现）。
4. 若**所有**上一轮问题状态均为"已修复"且"本轮新增"为空 → 本轮结论为"无新问题"，触发上层 loop 退出。

## 产出规范（markdown 结构固定）

产出追加到 `<target-requirement-dir>/自审报告.md`（**追加，不覆盖**；见 `_shared/file-conventions.md` §5.2）。

### 首次建档头部（仅 Round 1 写入）

```markdown
# 自审报告 - {编号} - {功能名}

> 对应需求：{编号}-{功能名}
> 审查者：self-review 子 skill（独立 subagent）
```

### 每轮节结构（必须按此顺序）

```markdown
## Round <N> - <YYYY-MM-DD HH:mm>

### 结论

<结论：通过 | 有 P1 待修 | 有 P0 待修>

<一段 2–3 句的总体判断>

### 问题清单

#### P0（必须修复）
- **[路径]** `<file-abs-path>:<line>` 问题简述
  - 引用：`<原代码行或片段，≤ 2 行>`
  - 说明：为何是问题（对应维度 N）
  - 建议：修法方向

#### P1（建议修复）
- **[路径]** `<file-abs-path>:<line>` 问题简述
  - 引用：`...`
  - 说明：...
  - 建议：...

<无 P0 或 P1 问题时本小节写 `- 无`，**禁止**省略小节标题>

### 附录

#### 维度结论矩阵
| 维度 | 结论 | 备注 |
|------|------|------|
| 1 需求覆盖 | 通过 / 有问题 | 涉及 FP-x, FP-y |
| 2 契约一致性 | ... | ... |
| 3 代码规范 | ... | ... |
| 4 影响面 | ... | ... |
| 5 单元测试 | ... | ... |
| 6 本轮增量 | N/A（Round 1） / ... | Round ≥ 2 时填 |

#### 本轮增量对比 <仅 Round ≥ 2 时填写本小节，Round 1 整节省略>
| 上轮问题 | 状态 | 说明 |
|---------|------|------|
| `<file>:<line>` ... | 已修复 / 部分 / 未修复 / 新引入 | ... |
```

### 问题清单硬约束

每条问题**必须**包含以下三项，缺一不可：
1. **文件路径**（绝对路径，自 `<project_root>` 起）
2. **行号**（`<file>:<line>` 形式；若是整文件级问题写 `<file>:*`）
3. **代码引用**（从该文件摘 ≤ 2 行原样片段，禁止改写）

缺任何一项的条目视为"基于想象报告"，禁止出现在报告中。

## 失败处理

| 情况 | 处理 |
|------|------|
| 派发上下文缺失（`需求.md` / diff / `code_conventions` 任一）| 不擅自继续；回传派发方"上下文不足：缺 X"，由 `fullstack-builder` 重新派发 |
| `git diff <session_base>` 为空 | **不视为通过**；回传"上下文不足：session_base 可能错误，或本会话无任何改动"，由 `fullstack-builder` 检查 session_base 绑定后重新派发。**严禁自动得出"通过"结论**。 |
| 找不到对应 FP 的实现代码 | 在维度 1 下记"未覆盖"进 P0；不得猜测存在于未读文件 |
| `code_conventions` 与项目实际风格冲突 | 以 `code_conventions` 为准；冲突点作为 P1 进问题清单，附"建议同步规约文件"的说明 |
| 上一轮 `自审报告.md` 解析失败（Round ≥ 2）| 本轮报告中标注"上轮报告不可解析，维度 6 降级为新增问题识别"，不强行对比 |

## 禁止事项

- **严禁自行修改代码**：本 skill 只审查、只报告；任何代码修改都交回 `fullstack-builder` 主会话。发现问题就写问题清单，不得 Edit / Write 源码文件。
- **严禁基于想象报告问题**：所有问题条目必须含真实存在的文件路径、行号、从文件中摘出的代码引用；不得凭猜测写"可能在 xxx 有问题"。
- **严禁由主会话直接执行**：本 skill 必须在独立 subagent 中运行（由 Agent 工具派发）；主会话"自己审自己"视同未审。
- **严禁覆盖 `自审报告.md`**：多轮追加，Round-N 顺序严格递增（见 `_shared/file-conventions.md` §5.2）。
- **严禁硬编码代码规范**：维度 3 只从 `code_conventions` 读；任何写在 SKILL.md 内的具体规则示例都必须标"示例不硬编码"。
- **严禁跳过 Round ≥ 2 的增量对比**：不得只做本轮新增识别、不对上轮问题逐条定状态。
- **严禁硬编码项目名 / 路径 / 技术栈**：全部引用 `<project_root>` / `<target-requirement-dir>` 等语义变量。
- **严禁产出没有行号和代码引用的问题条目**。
- **严禁私自扩张维度**：只做定义的六维度；其它发现（如设计建议 / 重构想法）不得混入问题清单，可写入附录的"备注"列。
