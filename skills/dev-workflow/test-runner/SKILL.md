---
name: test-runner
description: 测试编排主 skill。当用户说"生成测试用例""生成测试""跑测试""做接口自动化""对这个需求测试"或键入 /test 时触发；读取 改动.md 后按 schema 生成 测试.md 四类用例 + automation/ 接口自动化脚本，运行脚本 loop 修正（最多 3 轮或用户终止），追加 测试报告.md（Run-N），并把 _overview.md 状态由 🟣 测试中 → ✅ 已完成
---

# Test Runner — 测试编排

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 用户意图是测试阶段任务，常见信号：
  - "生成测试用例" / "生成测试" / "跑测试" / "做接口自动化"
  - "测试这个需求" / "测试这个改动" / "对 <编号>-<功能名> 测试"
- `<target-requirement-dir>/改动.md` 已经存在（由 `fullstack-builder/subskills/change-summarizer` 产出），子需求状态通常为 🟣 测试中 / 🟢 开发中。

### 不适用场景

- 用户想写需求 / 拆需求 / 做可行性评估 → 交给 `product-designer`（/product）。
- 用户想开始开发 / 实现需求 → 交给 `fullstack-builder`（/fullstack）。
- `<target-requirement-dir>/改动.md` 不存在：**阻断**，提示用户先完成 `fullstack-builder` 的 Step 6（change-summarizer），`改动.md` 是本 skill 的唯一权威输入。
- 前端 UI 端到端自动化（Playwright / Cypress / Selenium / WebDriver）：**本版本明确不做**（见下方"范围外"）。

## 前置检查（Preflight）

**必须**先执行 `../_shared/preflight.md` 定义的全部步骤（**Step 1 → 2 → 2.5 → 3.0 → 3**）：

1. **Step 1** superpowers **硬依赖**检测；未装直接硬 fail 并输出引导话术，**禁止进入主流程**。
2. **Step 2** 项目适配：Read `../_shared/project-adapter.md`，按 Part 1→2→3→4 绑定下游变量：`project_root` / `requirements_dir` / `backend_dir` / `frontend_dir` / `test_dir` / `backend_stack` / `frontend_stack` / `test_backend_stack` / `test_frontend_stack` / `backend_cwd` / `frontend_cwd` / `test_cwd` / `code_conventions`。**测试栈独立识别**（详见 project-adapter §2.3.1）：先扫 `<test_dir>` 实际文件后缀，允许 `test_backend_stack` 与 `backend_stack` 异构（如后端 Node + 测试目录用 pytest）。
3. **Step 2.5** 记录 `session_base`（test-runner 一般不改代码，但保持接口一致）。
4. **Step 3.0** 推断 `<target-requirement-dir>`（**强制**）。
5. **Step 3** 输入就绪检查（按 preflight §3.3 test-runner 分支）：
   - **强制**：`<target-requirement-dir>/改动.md` 存在且可解析。
   - **推荐**：`<target-requirement-dir>/需求.md` 存在（用于对照 FP-N 覆盖度）；缺失时警告但允许继续。
   - 状态未推进到 🟣 测试中 / 🟢 开发中 → 警告并让用户确认后继续。

**N/A 短路**：`frontend_stack = N/A` → 跳过所有前端测试就绪判定，`test_frontend_stack` 视为 N/A，`测试.md` 的"前端手测清单"写 `N/A`。

**严禁跳过 Preflight**。

## 测试框架识别（从 Preflight `test_backend_stack` 推导）

本 skill **不自行判定栈**，只引用 Preflight（`project-adapter.md` Part 2.3）已绑定的变量。下表把 `test_backend_stack` 映射到本 skill 产出 `automation/` 脚本的具体写法。任一项未识别 → 回到 Preflight Step 2 ask 用户，不得默默取默认值。

| Preflight `test_backend_stack` | 后端测试框架组合 | automation/ 脚本命名 | 运行命令 | setup/teardown 惯例 |
|---|---|---|---|---|
| `junit5+restassured` | JUnit 5 + RestAssured（或 Spring Test `MockMvc` / `@SpringBootTest` + `TestRestTemplate`） | `src/test/java/.../<Feature>Test.java`（保留包路径） | `mvn -q test` 或 `./gradlew test` | `@BeforeEach` / `@AfterEach`；项目用 Testcontainers 则沿用 |
| `jest+supertest` | Jest + Supertest | `<feature>.test.js` / `<feature>.test.ts` | `npm test` / `pnpm test` / `yarn test`（按锁文件） | `beforeAll` / `beforeEach` / `afterAll` |
| `vitest+supertest` | Vitest + Supertest | `<feature>.test.ts` / `<feature>.spec.ts` | `npx vitest run` 或 `npm run test`（若有 vitest 脚本） | `beforeAll` / `beforeEach` / `afterAll`（vitest 兼容 jest 风格） |
| `mocha+chai+supertest` | Mocha + Chai + Supertest（Node 老项目） | `<feature>.test.js` / `test/<feature>.js` | `npx mocha` 或 `npm test`（按 `mocharc` 配置） | `before` / `beforeEach` / `after` |
| `pytest+httpx` | pytest + httpx（async 友好） | `test_<feature>.py` | `pytest -q` | pytest fixture（`@pytest.fixture` + `yield`） |
| `pytest+requests` | pytest + requests（同步 HTTP） | `test_<feature>.py` | `pytest -q` | 同上 |
| `pytest+respx` | pytest + httpx + respx（mock async HTTP） | `test_<feature>.py` | `pytest -q` | 同上 + `respx_mock.start/stop` |
| `go-test` | `testing` + `net/http/httptest`（或 `httptest.NewServer`；表驱动用例） | `<feature>_test.go` | `go test ./...` 或 `go test ./<pkg>/...` | `TestMain` 或表驱动 per-case setup，`t.Cleanup(...)` |
| `cargo-test` | Rust 原生 `#[test]` + `reqwest`（HTTP 集成）或 `actix-web::test` | `tests/<feature>.rs` 或 `src/<mod>.rs` 内 `#[cfg(test)]` mod | `cargo test` | `#[fixture]`（rstest）或函数内 setup + RAII teardown |
| `xunit` | xUnit + `WebApplicationFactory<TStartup>`（ASP.NET Core） | `<Feature>Tests.cs` | `dotnet test` | `IClassFixture<>` / `IAsyncLifetime` |
| `nunit` | NUnit + 同上 | `<Feature>Tests.cs` | `dotnet test` | `[OneTimeSetUp]` / `[SetUp]` / `[TearDown]` |
| `mstest` | MSTest + 同上 | `<Feature>Tests.cs` | `dotnet test` | `[ClassInitialize]` / `[TestInitialize]` / `[TestCleanup]` |
| `rspec+rack-test` | RSpec + Rack::Test（Rails request specs） | `spec/requests/<feature>_spec.rb` | `bundle exec rspec` | `before(:each)` / `after(:each)` / `let` |
| `phpunit` | PHPUnit | `tests/<Feature>Test.php` | `vendor/bin/phpunit` | `setUp()` / `tearDown()` |
| `phpunit+laravel-test` | PHPUnit + Laravel `TestCase`（feature tests） | `tests/Feature/<Feature>Test.php` | `php artisan test` 或 `vendor/bin/phpunit` | `setUp()` / `RefreshDatabase` trait |
| `exunit` | ExUnit（Phoenix `ConnCase` 用于 controller 测试） | `test/<feature>_test.exs` | `mix test` | `setup` / `setup_all` |
| `scalatest` | ScalaTest（搭配 Akka HTTP TestKit / Play TestServer） | `src/test/scala/.../<Feature>Spec.scala` | `sbt test` | `BeforeAndAfterEach` / `BeforeAndAfterAll` |
| 其他未识别 | 回到 Preflight Step 2 ask 用户具体框架后再产出 | 按用户答复 | 按用户答复 | 按用户答复 |

**前端测试栈说明**：本版本前端**不做 UI 自动化**（Playwright / Cypress / Selenium / WebDriver 等均在范围外）。`test_frontend_stack`（如 `vitest` / `jest`）仅用于本项目已有的组件级单元测试，本 skill **不**在 `automation/` 下生成前端 UI 脚本。前端部分以**手测清单**形式落在 `测试.md` 中（见 Step 3）。

## 主流程

```
Step 1 Preflight（Read _shared/preflight.md）
  → Step 2 解析 改动.md（FP + 接口三节 + 影响面 + 前端交互点）
    → Step 3 生成 测试.md（功能 / 接口 / 回归 / 前端手测）
      → Step 4 生成 automation/ 接口自动化脚本
        → Step 5 运行验证 loop（失败修正，最多 3 轮或用户终止）
          → Step 6 追加 测试报告.md（Run-N）
            → Step 7 更新 _overview.md（🟣 → ✅）并汇报
```

### Step 1 — Preflight

按"前置检查（Preflight）"节执行；结束后必须已绑定：`<target-requirement-dir>`、`test_backend_stack`、`test_frontend_stack`。

### Step 2 — 解析 `改动.md`（按固定字段枚举）

Read `<target-requirement-dir>/改动.md`，严格按 `../_shared/requirement-schema.md` §2 解析。字段顺序固定；缺章节按 §3.2 ask 用户（**禁止猜测或擅自回填**）。

按以下定位与正则逐项提取：

| 提取目标 | 定位 / 正则 | 来源章节 |
|---|---|---|
| 功能点清单 | 行匹配 `^- \[( |x)\] FP-(\d+)`（捕获勾选态 + 编号 + 描述） | `## 功能点清单` |
| 新增接口 | 先定位 `## 接口变更` → `### 新增`，再用 `\*\*\`([A-Z]+)\s+(/\S+)\`\*\*` 捕获 method + path，再读其下 `用途 / 请求 / 响应 / 错误码 / 鉴权` 子字段 | `### 新增` |
| 修改接口 | 同上换子节；每条含 `变更前 / 变更后 / 兼容性` | `### 修改` |
| 废弃接口 | 同上换子节；每条含 `废弃原因 / 替代方案 / 预计下线版本` | `### 废弃` |
| 定时任务变更 | 在 `## 非 HTTP 契约` 下定位 `### 定时任务变更`，按 `- \*\*\`(.+?)\`\*\*` 枚举 | `### 定时任务变更` |
| 事件监听变更 | 同上换子节 | `### 事件监听变更` |
| 消息通道变更 | 同上换子节 | `### 消息通道变更` |
| 邮件/通知通道变更 | 同上换子节 | `### 邮件/通知通道变更` |
| 数据库变更 | 整节按行枚举 | `## 数据库变更` |
| 配置变更 | 整节按行枚举 | `## 配置变更` |
| 影响面 | 整节按行枚举（每条"功能名称 + 原因 + 回归建议"） | `## 影响面` |
| 前端交互点 | 整节按行枚举（每条"页面/组件 + 用户操作路径 + 手测关注点"） | `## 前端交互点` |

**缺节 / 格式异常处理**：
- `### 新增` / `### 修改` / `### 废弃` 三节中任一小节写 `无` → 对应条目数记为 0，**不崩溃**、不生成空壳用例。
- 三级小节全部缺失或章节 `## 接口变更` 本身缺失 → 按 schema §3.2 ask 用户修正 `改动.md`，不自动回填。
- 接口标识格式偏离（如非粗体 `POST /api/x`、method 小写、路径不以 `/` 开头） → 显式告知用户字段格式异常并提示修正（参考"失败处理"表），不擅自"容错"识别。

（可选）Read `<target-requirement-dir>/需求.md`，提取 FP-N 名称、AC-N，用于在 `测试.md` 中把每条功能用例回链到具体 FP / AC（覆盖度对照）。

### Step 3 — 生成 `测试.md`（四类用例齐全）

文件路径：`<target-requirement-dir>/测试.md`。覆盖策略：已存在 → 按 `../_shared/file-conventions.md` §5.1 提示覆盖（覆盖 / 备份后覆盖 / 取消）。

**必须**包含以下四类用例，缺一不可；无对应数据时保留章节并写 `无`：

#### 3.1 功能测试用例（正 / 反 / 边界）

- 以 `改动.md` 的 `## 功能点清单`（FP-N）为主索引，对每条 FP 生成至少一组用例；若 `需求.md` 可读，补充对应 AC-N 验收点。
- 每条用例结构：

  ```markdown
  - FT-{N} {用例名称}（对应 FP-{X} / AC-{Y}）
    - 类型：正向 / 反向 / 边界
    - 前置条件：...
    - 步骤：...
    - 预期：...
  ```

- **正 / 反 / 边界**三类必须同时覆盖关键功能点；至少每个 FP 有 1 条正向 + 1 条反向或边界。

#### 3.2 接口测试用例（每个变更接口一组）

- 对 `改动.md` `### 新增` / `### 修改` / `### 废弃` 中**每一条接口**生成一组用例：
  - **新增接口**：至少含"参数合法（正向）+ 参数缺失/非法（反向）+ 边界值 + 鉴权通过/失败 + 错误码分支"。
  - **修改接口**：对比"变更前后"行为差异；若为破坏性变更，补迁移相关用例。
  - **废弃接口**：验证返回废弃提示 / 正确路由到替代接口（若项目约定）。
- 每条用例结构：

  ```markdown
  - AT-{N} {接口} - {场景}
    - 方法 / 路径：POST /api/xxx
    - 请求：body / query / headers
    - 预期响应：status + data + 错误码
    - 鉴权：...
    - 关联自动化：automation/{脚本名}#{测试方法名}（Step 4 产出后回填）
  ```

#### 3.3 回归测试用例（基于影响面）

- 以 `改动.md` 的 `## 影响面` 每一条为索引，生成对应回归用例，防止波及现有功能。
- 每条用例结构：

  ```markdown
  - RT-{N} {受影响功能} 回归
    - 受影响原因：...
    - 回归建议（来自 改动.md）：...
    - 步骤 / 预期：...
  ```

- `## 影响面` 写 `无` 时，本节写 `- 无（改动.md 声明无影响面）`，但需在文末提示"请人工复核是否确实无影响"。

#### 3.4 前端手测清单（UI 自动化范围外）

- 以 `改动.md` 的 `## 前端交互点` 每一条为索引生成手测条目；不生成任何 Playwright / Cypress / Selenium 脚本。
- 每条用例结构：

  ```markdown
  - MT-{N} {页面或组件} - {操作场景}
    - 用户操作路径：...（来自 改动.md）
    - 手测关注点：校验 / 边界 / 错误态 / 鉴权态 / 空态 / 加载态（按 改动.md 列出的关注点展开）
    - 预期：...
  ```

- `## 前端交互点` 写 `无` / `N/A`（纯后端变更）时，本节写 `- 无（纯后端改动）`。

### Step 4 — 生成 `automation/` 接口自动化脚本

#### 4.0 路径策略（per-requirement vs centralized）

由 `options.automation_strategy`（`config.yml`）决定，详见 `_shared/file-conventions.md` §7.1：

| 策略 | 脚本位置 | 适用 |
|------|---------|------|
| `per-requirement`（默认） | `<target-requirement-dir>/automation/` | 脚本与需求强关联 |
| `centralized` | `<test_dir>/<编号>-<功能名>/` | 项目已有 `<test_dir>` 下的统一测试基建（共享 fixture / conftest / pom 模块） |

`centralized` 模式下，必须在 `<target-requirement-dir>/automation.md` 留指针文件指向真实位置。

#### 4.1 生成原则

- **不硬编码测试框架**：仅根据 Preflight 绑定的 `test_backend_stack` 选择写法。允许 `test_backend_stack` 与 `backend_stack` 异构（按 project-adapter §2.3.1 的实际识别）。
- **不生成前端 UI 自动化**（Playwright / Cypress / Selenium）。
- **覆盖所有外部可观测变更**：
  - HTTP：`改动.md` 所有接口变更（新增 / 修改 / 废弃 三节）每个接口一个测试方法。
  - 非 HTTP：定时任务 / 事件 / 消息 / 邮件，按 `_shared/file-conventions.md` §9 "非 HTTP 改动的自动化策略"产出（典型实现：Spring `@SpringBootTest` 注入 Bean 手动调；Node 把 cron handler 抽纯函数直测；MQ 测试生产者+消费者 Mock；邮件 Mock `MailSender` + 模板渲染断言）。
- **脚本独立可运行**：由项目已有测试基建驱动；执行命令的 **cwd** 按 Preflight 绑定的变量（`<test_cwd>` 或 `<backend_cwd>`），见 `_shared/project-adapter.md` Part 4.2。若 `automation/` 脚本未在项目现有测试发现路径内，需在该目录补最小运行入口（按栈：`pom.xml` 子模块 / `package.json` / `pytest.ini` + `conftest.py` / `go.mod`）。
- **每条用例包含四要素**：**setup** → **调用** → **断言** → **teardown**。
- **按 `code_conventions`**：若 Preflight 读到项目对测试写法的约定（命名、目录、断言风格），按约定落地。

#### 4.2 覆盖率回填

- 脚本生成完毕后，回到 `测试.md` §3.2 每条接口用例，把 `关联自动化：...` 回填为具体脚本路径 + 测试方法名。
- 自动化未覆盖的条目（如"废弃接口的下线公告文案验证"）保留"关联自动化：无，转手测"。

#### 4.3 覆盖策略

- 每个脚本文件按 `../_shared/file-conventions.md` §5 "按文件提示覆盖"处理：已存在则逐文件询问（覆盖 / 备份后覆盖 / 取消）；新增脚本不询问。

### Step 5 — 运行验证 loop

**目标**：确认 Step 4 产出的脚本能真正跑起来并正确反映改动。

#### 5.1 运行

按 Preflight 绑定的栈执行对应命令（`mvn test` / `./gradlew test` / `npm test` / `pytest` / `go test ./...`；具体见上方"测试框架识别"表）。**必须**捕获真实输出，**不得**凭记忆断言"应该通过"（对齐 `fullstack-builder/SKILL.md` Step 4 verification 纪律）。

#### 5.2 失败修正循环（**归因可操作**）

- **全部通过**：loop 结束，进入 Step 6。
- **失败**：按下表判定归因后采取对应动作：

  | 归因 | 判定依据（任一满足即归此类） | 处理 |
  |------|------------------------------|------|
  | **脚本自身错误** | 错误类型为 `AssertionError` 但断言常量明显写错；或异常堆栈在 `automation/` 脚本内（非 `<backend_dir>`）；或 `SyntaxError` / `ImportError` / 数据准备步骤报错 | 回到 Step 4 修脚本 |
  | **被测代码真问题** | 异常堆栈深入 `<backend_dir>` 的应用代码；或断言失败的"实际值"与"期望值"差异指向业务逻辑错误（不是断言写错） | **不修代码**，记录到本轮 `测试报告.md`，向用户汇报建议回 `fullstack-builder` 修复 |
  | **改动.md 与代码不一致** | 接口路径 / 方法 / 字段名 / 错误码在 `改动.md` 中描述与代码实际不符（404 / 字段缺失 / 类型不符）| 回 `change-summarizer` 重跑或人工修正 `改动.md`，**不擅改** |

- 每次"再跑"视为新一轮，Run 编号 +1（见 Step 6）。

#### 5.3 退出条件（三选一即退出 loop）

对齐 `fullstack-builder/SKILL.md` Step 5 self-review loop 的退出风格：

1. **无失败**：当轮所有脚本通过。
2. **达最大轮次**：`options.test-fix-max-rounds`（默认 **3**；可由 `config.yml` 覆盖）。达上限仍有失败时，**不阻断 Step 6**（测试报告仍要产出），但把遗留失败显式汇报给用户决定（继续修 / 带着失败进入总结 / 终止）。（与 fullstack-builder self-review loop 不同：测试失败也要落报告以便追溯与人工决策；自审失败则会阻断 change-summarizer。）
3. **用户手动终止**：用户在任一轮间隙明确说"停 / 够了 / 不再跑"。

### Step 6 — 追加 `测试报告.md`（Run-N，**永不覆盖**）

文件路径：`<target-requirement-dir>/测试报告.md`。

**追加策略**（严格对齐 `../_shared/file-conventions.md` §5 / §5.2）：

- 首次创建：写入一级标题 `# 测试报告 - {编号} - {功能名}`，随后 `## Run 1 - YYYY-MM-DD HH:mm` 起。
- 已存在：**禁止覆盖**；读出当前最大 Run-N，本次以 `## Run {N+1} - YYYY-MM-DD HH:mm` 追加。

每个 Run-N 节至少包含：

```markdown
## Run {N} - YYYY-MM-DD HH:mm

- 执行环境：{test_backend_stack} / 本地 / CI
- 运行命令：...
- 用例总数：功能 {a} / 接口 {b} / 回归 {c} / 前端手测 {d}
- 自动化覆盖率：自动化覆盖接口数 / 接口总数 = 百分比
- 执行结果：通过 {x} / 失败 {y} / 跳过 {z}
- 失败用例清单：
  - AT-{N} {接口} - {场景}：失败原因摘要 + 复现步骤 + 归属（脚本问题 / 代码问题 / 改动.md 不一致）
- 本轮修正动作：（Step 5 中做了什么修复）
- 结论：全部通过 / 仍有失败（附数量）/ 用户终止
```

### Step 7 — 更新 `_overview.md` 并汇报

**统一协议**：本步骤的"读-改-写"算法严格遵循 [`../_shared/file-conventions.md`](../_shared/file-conventions.md) §10「`_overview.md` 写入算法（统一协议）」；本主 skill 仅作为 §10.3 "触发点"表中 `test-runner` 行的执行者，不重复实现算法逻辑。

- 在 `<requirements_dir>/_overview.md` 中把目标子需求状态从 🟣 测试中 → ✅ 已完成（触发点见 `../_shared/file-conventions.md` §4.2"🟣 → ✅"行）。
- **触发条件**：最近一次 `Run-N` 结论为"全部通过"。若 Step 5 loop 达 max-rounds 仍有失败、或用户终止时仍有失败：状态**保留** 🟣 测试中，在"备注"列写入"测试 Run-{N} 存在失败：{简述}，待人工决策"；允许非线性回退 🟣 → 🟢（见 §4.3）。
- 汇报向用户输出的最小信息：
  - 当前编号 / 功能名
  - 产物绝对路径：`测试.md` / `automation/` / `测试报告.md`
  - 本次 Run-N 结论摘要（通过 / 失败计数 + 关键失败条目）
  - 下一步建议（如"状态已推进到 ✅，可关单" / "请回 `/fullstack` 修复失败用例暴露的代码问题"）

## 子 skill 调用

本 skill **无子 skill**（与 Plan Task 3.1"单文件 skill"一致）。不派发 Agent 子会话；全部步骤在主会话内完成。

## 产出规范

| 产物 | 路径 | 覆盖策略 |
|------|------|---------|
| `测试.md` | `<target-requirement-dir>/测试.md` | 提示覆盖（`_shared/file-conventions.md` §5.1） |
| `automation/*` | `<target-requirement-dir>/automation/` 下脚本文件 | 按文件提示覆盖；新增脚本不询问 |
| `测试报告.md` | `<target-requirement-dir>/测试报告.md` | **追加 Run-N**（严禁覆盖；见 `_shared/file-conventions.md` §5.2） |
| `_overview.md` 状态列 | `<requirements_dir>/_overview.md` | 行级更新（🟣 → ✅；或保持 🟣 并写备注） |

所有路径在本 SKILL.md 中**只用语义变量**：`<project_root>` / `<requirements_dir>` / `<target-requirement-dir>` / `<backend_dir>` / `<frontend_dir>` / `<test_dir>`。

## 范围外（本版本不做）

- **前端 UI 自动化**（Playwright / Cypress / Selenium / WebDriver / TestCafe 等）——本版本明确不做。前端部分以 `测试.md` §3.4 "前端手测清单"呈现；`automation/` 目录**不得**包含任何前端 UI 自动化脚本。Plan 后续版本再评估。
- **性能 / 压力 / 稳定性测试**（JMeter / k6 / Locust / wrk 等）。
- **跨项目 skill 中心化管理**（每个项目内独立维护 `.claude/skills/`）。
- **测试数据大规模构造 / 生产数据脱敏**——保持用例内自包含的 setup/teardown。
- **CI 配置文件生成**（`.github/workflows/*` / `gitlab-ci.yml` 等）——脚本可被 CI 调用，但本 skill 不改 CI 配置。

## 失败处理

| 情况 | 处理 |
|------|------|
| Preflight Step 3 `改动.md` 缺失 | 阻断，ask 用户先完成 `fullstack-builder` Step 6 的 `change-summarizer` |
| 状态未到 🟣 / 🟢 | 警告并 ask 用户是否确认继续；用户确认后继续并在 `测试报告.md` 备注异常推进 |
| `改动.md` `### 新增` / `### 修改` / `### 废弃` 某节写 `无` | 对应条目数记 0，不生成空壳用例，不报错（字段解析稳定性基线） |
| `改动.md` 三级小节全部缺失 / `## 接口变更` 章节缺失 | 按 `_shared/requirement-schema.md` §3.2 ask 用户修正；禁止擅自回填 |
| `改动.md` 接口标识格式异常（如非粗体、method 小写、缺代码块） | 显式向用户列出异常行号 + 正则期望，ask 修正；不"容错"解析 |
| `test_backend_stack` / `test_frontend_stack` 未识别 | 回 Preflight Step 2，按 `project-adapter.md` Part 2.4 ask 用户，不默认取值 |
| `automation/` 脚本无法独立运行（缺配置 / 缺依赖） | 在脚本目录补最小运行入口（按栈：`pom.xml` / `package.json` / `pytest.ini` / `go.mod`）；仍失败则 ask 用户 |
| Step 5 反复失败 | 区分 脚本问题 / 代码问题 / `改动.md` 不一致 三类归属：前者回 Step 4；中者不改代码、汇报用户回 `/fullstack`；后者回 `change-summarizer` |
| Step 5 达 max-rounds 仍有失败 | **不阻断 Step 6**；`测试报告.md` 如实记录失败 + 归属；状态保留 🟣 + 备注；ask 用户决策 |
| `测试报告.md` 已存在 | **禁止覆盖**；按 `_shared/file-conventions.md` §5.2 读出最大 Run-N 后以 `## Run {N+1}` 追加 |
| `_overview.md` 不存在 | 创建文件写入表头（按 `_shared/file-conventions.md` §3.2），再写当前行 |
| superpowers 未装 | Preflight Step 1 已硬 fail，本流程不会到这里 |

## 禁止事项

- **不硬编码测试框架**：不得在本 SKILL.md 或生成的脚本中写死"用 JUnit / Jest / pytest"；一律引用 Preflight 绑定的 `test_backend_stack`，按"测试框架识别"表映射写法。
- **不生成前端 UI 自动化脚本**（Playwright / Cypress / Selenium / WebDriver / TestCafe 等），前端部分仅以 `测试.md` §3.4 手测清单形式呈现。
- **不跳过 Preflight**，即便用户催促。
- **不擅自回填 `改动.md` 缺失字段**：按 `_shared/requirement-schema.md` §3.2 ask 用户；禁止猜测 / 自动构造默认值。
- **不覆盖 `测试报告.md`**：追加 Run-N，编号严格递增；见 `_shared/file-conventions.md` §5 / §5.2。
- **不在 Step 5 里改被测代码**：脚本暴露的代码问题一律退回 `/fullstack`；本 skill 只修脚本 + `改动.md` 不一致。
- **不硬编码项目名**（如 `shangyunbao-arena` / `asms` / `taikeduo`）或根级目录名（如 `backend` / `frontend` / `test` / `product`）；全部引用 Preflight 绑定的语义变量。
- **不在未识别栈时默默取默认值**：必须 ask 用户（对齐 `project-adapter.md` Part 2.4）。
- **不声称 Run 通过而未看到实际命令输出**：对齐 `fullstack-builder/SKILL.md` Step 4 verification 纪律。
- **不自动 git commit**：本 skill 只落盘 `测试.md` / `automation/*` / `测试报告.md`，并行级更新 `_overview.md`；不执行 `git add` / `git commit` / `git push`。
- **不绕过 Preflight 调用 `superpowers:*`**：所有 superpowers 调用必须在 Preflight 通过后进行。
- **不把手测清单写入 `automation/`**：手测留在 `测试.md` §3.4（对齐 `_shared/file-conventions.md` §7）。
