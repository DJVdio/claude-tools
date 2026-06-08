---
name: test-runner
description: 测试编排主 skill。当用户说"生成测试用例""生成测试""跑测试""做接口自动化""做 E2E""测一下""对这个需求测试"或键入 /test 时触发；读取 改动.md + git diff 后全量生成单元测试、集成测试、E2E 测试三层测试用例文档 + 可执行脚本，运行验证 loop 修正（最多 3 轮或用户终止），追加 测试报告.md（Run-N），并把 _overview.md 状态由 🟣 测试中 → ✅ 已完成
---

# Test Runner — 测试编排

> **以下所有 `<尖括号>` 必须替换为实际内容；不得照抄占位符本身。**

## 何时使用

- 用户意图是测试阶段任务，常见信号：
  - "生成测试用例" / "生成测试" / "跑测试" / "做接口自动化"
   - "测试这个需求" / "测试这个改动" / "对 <编号>-<功能名> 测试"
   - "做 E2E" / "跑 Playwright" / "前端测试"
- `<target-requirement-dir>/改动.md` 已经存在（由 `fullstack-builder/subskills/change-summarizer` 产出），子需求状态通常为 🟣 测试中 / 🟢 开发中。

### 不适用场景

- 用户想写需求 / 拆需求 / 做可行性评估 → 交给 `product-designer`（/product）。
- 用户想开始开发 / 实现需求 → 交给 `fullstack-builder`（/fullstack）。
- `<target-requirement-dir>/改动.md` 不存在：**阻断**，提示用户先完成 `fullstack-builder` 的 Step 6（change-summarizer），`改动.md` 是本 skill 的唯一权威输入。

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

**N/A 短路**：`frontend_stack = N/A` → 跳过所有前端/E2E 测试就绪判定，`test_frontend_stack` 视为 N/A；`测试.md` §3.3 E2E 用例写 `N/A（纯后端项目）`，不安装 Playwright、不生成 E2E 脚本。

**严禁跳过 Preflight**。

## 测试框架识别

本 skill **不自行判定栈**，只引用 Preflight（`project-adapter.md` Part 2.3）已绑定的变量。

### 后端测试栈（单元测试 + 集成测试共用）

下表把 `test_backend_stack` 映射到本 skill 产出的后端自动化脚本写法。任一项未识别 → 回到 Preflight Step 2 ask 用户，不得默默取默认值。

| Preflight `test_backend_stack` | 测试框架组合 | automation/ 脚本命名 | 运行命令 | setup/teardown 惯例 |
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

### E2E 测试栈（Playwright 统一）

当 `frontend_dir` 非 N/A 且 `改动.md` 的 `## 前端交互点` 有内容时，自动启用 Playwright E2E 测试层：

| 维度 | 取值 |
|------|------|
| 测试框架 | Playwright（`@playwright/test`） |
| 脚本命名 | `e2e/<feature-name>.spec.ts`，放 `<target-requirement-dir>/automation/e2e/` |
| 运行命令 | `npx playwright test --config=<config-path>` |
| 浏览器 | Chromium（默认）；必要时覆盖 Firefox / WebKit |
| setup/teardown | `test.beforeEach` / `test.afterEach`；全局 setup 用 `globalSetup` / `project.setup` |
| 前端 dev server | 自动检测 `package.json` `scripts.dev`（依次尝试 `dev` / `serve` / `start`）并 `child_process.spawn` |

> **E2E 层与后端层不互斥**：当需求同时有后端接口变更和前端交互变更时，两套测试都会生成并运行。

## 主流程（统一流水线）

```
Step 1 Preflight（Read _shared/preflight.md）
  → Step 2 解析 改动.md + git diff（全量变更分析）
    → Step 3 生成 测试.md（单元测试 / 接口集成 / E2E / 回归 四层）
      → Step 4 生成 automation/ 脚本（分层产出）
         4a. 后端：单元测试 + 接口集成测试（按 test_backend_stack）
         4b. 前端：Playwright E2E 脚本（若 frontend_dir 非 N/A 且有前端交互）
        → Step 5 运行验证 loop（按层依次运行：单元→集成→E2E）
          → Step 6 追加 测试报告.md（Run-N）
            → Step 7 更新 _overview.md（🟣 → ✅）并汇报
```

### Step 1 — Preflight

按"前置检查（Preflight）"节执行；结束后必须已绑定：`<target-requirement-dir>`、`test_backend_stack`、`test_frontend_stack`、`backend_dir`、`frontend_dir`。

### Step 2 — 解析 `改动.md` + git diff（全量变更分析）

#### 2.1 解析 `改动.md`

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

#### 2.2 git diff 分析

读**实际变更代码**辅助生成各层测试用例：

```
git diff <session_base> -- <backend_dir>  （后端变更：辅助单元/集成测试）
git diff <session_base> -- <frontend_dir> （前端变更：辅助 E2E 测试）
```

从后端 diff 中提取：
- 新增/修改的 Service 类、Controller 类、Repository 类名和方法签名
- 新增/修改的 DTO 字段、校验注解
- 新增/修改的业务逻辑分支（if/else、switch、异常处理）
- 新增/修改的 SQL 语句或 ORM 查询

从前端 diff 中提取：
- 新增/修改的组件名、页面路径（Vue `pages/` / React `pages/` / 路由配置）
- 新增/修改的 UI 元素（按钮、表单、列表、弹窗等）
- 交互流程变化（跳转、提交、筛选、分页等）
- API 调用层变化（新增请求、参数变化）

（可选）Read `<target-requirement-dir>/需求.md`，提取 FP-N 名称、AC-N，用于在 `测试.md` 中把每条功能用例回链到具体 FP / AC（覆盖度对照）。

### Step 3 — 生成 `测试.md`（四层用例齐全）

文件路径：`<target-requirement-dir>/测试.md`。覆盖策略：已存在 → 按 `../_shared/file-conventions.md` §5.1 提示覆盖（覆盖 / 备份后覆盖 / 取消）。

**必须**包含以下四层用例，缺一不可；无对应数据时保留章节并写 `无`：

#### 3.1 单元测试用例（函数/方法级）

- 基于 `git diff` 识别的后端新增/修改的类和方法，按 FP-N 分组生成单元测试。
- 覆盖每个变更方法的：
  - **正向**：正常输入 → 正确返回值
  - **反向**：非法参数 → 预期异常
  - **边界**：null / 空集合 / 极限值 / 特殊字符
- 对 Service 层：Mock Repository/DAO 依赖，只测业务逻辑。
- 对工具类/纯函数：直接测，不 Mock。
- 每条用例结构：

  ```markdown
  - UT-{N} {类名}.{方法名} - {场景}（对应 FP-{X}）
    - 类型：正向 / 反向 / 边界
    - Mock：{依赖列表}
    - 输入：...
    - 预期：...
  ```

- `git diff` 无后端逻辑变更（纯前端/纯配置）时，本节写 `- 无（本次无后端逻辑变更）`。

#### 3.2 接口集成测试用例（API 级）

- 对 `改动.md` `### 新增` / `### 修改` / `### 废弃` 中**每一条接口**生成一组集成测试用例：
  - **新增接口**：至少含"参数合法（正向）+ 参数缺失/非法（反向）+ 边界值 + 鉴权通过/失败 + 错误码分支"。
  - **修改接口**：对比"变更前后"行为差异；若为破坏性变更，补迁移相关用例。
  - **废弃接口**：验证返回废弃提示 / 正确路由到替代接口（若项目约定）。
- 每条用例结构：

  ```markdown
  - IT-{N} {接口} - {场景}
    - 方法 / 路径：POST /api/xxx
    - 请求：body / query / headers
    - 预期响应：status + data + 错误码
    - 鉴权：...
    - 关联自动化：automation/{脚本名}#{测试方法名}（Step 4 产出后回填）
  ```

- `变动.md` `### 新增` + `### 修改` + `### 废弃` 全为 `无` 时，本节写 `- 无（本次无接口变更）`。
- 非 HTTP 变更（定时任务/事件/消息/邮件）仍落本节，按 `_shared/file-conventions.md` §9 策略描述用例。

#### 3.3 E2E 测试用例（用户端到端）

- 仅当 `改动.md` 的 `## 前端交互点` 有内容时生成；否则本节写 `- 无（纯后端/无前端交互改动）`。
- 以每条页面/组件交互点为主索引，结合 `git diff` 识别的 UI 元素，生成端到端用例：
  - **正向**：完整用户操作路径 → 预期结果
  - **反向**：错误操作 → 错误提示 / 兜底
  - **边界**：空态 / 极值输入 / 超长文本 / 并发点击
- 对 E2E 中涉及的后端接口调用，列明预期请求/响应。
- 每条用例结构：

  ```markdown
  - ET-{N} {页面} - {操作场景}（对应 FP-{X} / 交互点-{Y}）
    - 类型：正向 / 反向 / 边界
    - 用户操作路径：...（来自 改动.md 交互点 + diff 识别的 UI 路径）
    - 断言要点：页面元素 / 跳转路由 / 接口响应 / 状态变化 / 错误态
    - 前置条件：登录态 / 数据准备 / 路由进入方式
    - 关联自动化：automation/e2e/{脚本名}#{test 名}（Step 4 产出后回填）
  ```

- 可选：若有视觉比对能力，追加 `VT-N` 布局快照用例。

#### 3.4 回归测试用例（基于影响面）

- 以 `改动.md` 的 `## 影响面` 每一条为索引，生成对应回归用例，防止波及现有功能。
- 每条用例结构：

  ```markdown
  - RT-{N} {受影响功能} 回归
    - 受影响原因：...
    - 回归建议（来自 改动.md）：...
    - 测试层级：单元 / 集成 / E2E（按受影响功能性质定）
    - 步骤 / 预期：...
  ```

- `## 影响面` 写 `无` 时，本节写 `- 无（改动.md 声明无影响面）`，但需在文末提示"请人工复核是否确实无影响"。

### Step 4 — 生成 `automation/` 脚本（分层产出）

#### 4.0 路径策略

由 `options.automation_strategy`（`config.yml`）决定，详见 `_shared/file-conventions.md` §7.1：

| 策略 | 脚本位置 | 适用 |
|------|---------|------|
| `per-requirement`（默认） | `<target-requirement-dir>/automation/` | 脚本与需求强关联 |
| `centralized` | `<test_dir>/<编号>-<功能名>/` | 项目已有 `<test_dir>` 下的统一测试基建 |

`centralized` 模式下，必须在 `<target-requirement-dir>/automation.md` 留指针文件指向真实位置。

#### 4.1 层 A — 后端单元测试脚本

- **目标**：覆盖 `测试.md` §3.1 的每条 UT-N。
- **框架**：按 `test_backend_stack` 映射表选择写法。
- **位置**：`automation/unit/<feature>.<ext>`（如 `automation/unit/user-service.test.ts`）。
- **每条用例独立可运行**：含 import、Mock setup、断言、cleanup。
- 生成后回填 `测试.md` §3.1 的 `关联自动化` 字段。

#### 4.2 层 B — 后端接口集成测试脚本

- **目标**：覆盖 `测试.md` §3.2 的每条 IT-N。
- **框架**：按 `test_backend_stack` 映射表选择写法。
- **位置**：`automation/api/<feature>.<ext>`（如 `automation/api/user-controller.test.ts`）。
- **覆盖所有外部可观测变更**：
  - HTTP：`改动.md` 所有接口变更（新增 / 修改 / 废弃 三节）每个接口一个测试方法。
  - 非 HTTP：定时任务 / 事件 / 消息 / 邮件，按 `_shared/file-conventions.md` §9 策略产出。
- **每条用例包含四要素**：**setup** → **调用** → **断言** → **teardown**。
- **脚本独立可运行**：执行命令的 **cwd** 按 Preflight 绑定的变量（`<test_cwd>` 或 `<backend_cwd>`）。若 `automation/` 脚本未在项目现有测试发现路径内，补最小运行入口。
- 生成后回填 `测试.md` §3.2 的 `关联自动化` 字段。

#### 4.3 层 C — Playwright E2E 脚本

- **目标**：覆盖 `测试.md` §3.3 的每条 ET-N。
- **产出的前提**：`frontend_dir` 非 N/A 且 `改动.md` 的 `## 前端交互点` 有内容。
- **脚本命名**：`automation/e2e/<feature-name>.spec.ts`。
- **每条 E2E 场景一个 `test(...)` 块**，独立可跑。

##### 4.3.1 Playwright 前置检查

| 状态 | 处理 |
|------|------|
| `playwright` 已安装（`node_modules` 或 `npx playwright` 可用） | 跳过安装，只检查版本 |
| `playwright` 未安装 | 在 `<frontend_dir>` 执行 `npm install -D @playwright/test && npx playwright install chromium`，提示用户确认 |
| 项目已有 `playwright.config.ts` | 复用，追加配置（testDir 含 `automation/e2e/`） |
| 项目无 playwright config | 生成 `<frontend_dir>/playwright.config.ts` |

##### 4.3.2 Playwright config 模板

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './<relative-path-to-target-requirement-dir>/automation/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['html', { outputFolder: './playwright-report' }], ['list']],
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' },
    },
  ],
});
```

##### 4.3.3 脚本生成原则

- 用 **Page Object Model** 组织页面操作逻辑（项目已有则沿用，无则生成 `automation/e2e/pages/`）。
- 每条测试必须包含：**页面加载** → **用户操作** → **断言** → **截图或清理**。
- 生成后回填 `测试.md` §3.3 的 `关联自动化` 字段。

#### 4.4 覆盖策略

- 每个脚本文件按 `../_shared/file-conventions.md` §5 "按文件提示覆盖"处理：已存在则逐文件询问（覆盖 / 备份后覆盖 / 取消）；新增脚本不询问。

### Step 5 — 运行验证 loop（按层依次运行）

**目标**：确认 Step 4 产出的全部脚本能正确反映改动。

#### 5.1 运行顺序

按以下顺序依次执行，**每层全部通过才进入下一层**，任一层失败则进入 5.2 修正循环：

```
1. 单元测试层   → 命令按 test_backend_stack 映射表
2. 接口集成测试层 → 命令按 test_backend_stack 映射表
3. E2E 测试层    → npx playwright test（若存在）
```

#### 5.2 E2E 层特殊处理（dev server）

进入 E2E 层时，先启动前端 dev server：

1. 读取 `<frontend_dir>/package.json` `scripts` 键，依次尝试 `dev` → `serve` → `start`，取第一个存在的。
2. 用 `child_process.spawn` 启动 dev server，等待端口就绪（默认 `5173` / `3000`）。
3. 将端口注入环境变量 `BASE_URL`，传给 Playwright。
4. 超时 30 秒，超时则提示用户手动启动。

运行完毕自动 kill dev server 子进程。

#### 5.3 失败修正循环

- **全部通过**：loop 结束，进入 Step 6。
- **失败**：按下表判定归因后采取对应动作：

  | 归因 | 判定依据（任一满足即归此类） | 处理 |
  |------|------------------------------|------|
  | **脚本自身错误** | 断言常量写错；堆栈在 `automation/` 内；SyntaxError / ImportError | 回到 Step 4 修对应层脚本 |
  | **被测代码真问题** | 堆栈深入应用代码；实际值与期望值差异指向业务逻辑错误 | **不修代码**，记录到 `测试报告.md`，汇报用户回 `fullstack-builder` 修复 |
  | **改动.md 与代码不一致** | 接口路径/字段/错误码在 `改动.md` 中与代码不符 | 回 `change-summarizer` 或人工修 `改动.md` |
  | **E2E 选择器错误** | Playwright Locator 超时 / strict mode violation / 元素未找到 | 修 E2E 脚本（选择器/等待策略） |
  | **dev server 异常** | 端口未就绪 / 编译错误 / HMR 崩溃 | 提示用户检查前端项目 |
  | **E2E 前端真问题** | 断言失败但选择器正确；页面渲染异常 | **不修代码**，记录后回 `fullstack-builder` |

- 每次"再跑"视为新一轮，Run 编号 +1。
- **一轮内修正范围不限层**：可以同时修单元 + 集成 + E2E 脚本。

#### 5.4 退出条件（三选一即退出 loop）

1. **无失败**：所有层全部通过。
2. **达最大轮次**：`options.test-fix-max-rounds`（默认 **3**）。达上限仍有失败时，**不阻断 Step 6**，把遗留失败汇报给用户决定。
3. **用户手动终止**。

### Step 6 — 追加 `测试报告.md`（Run-N，**永不覆盖**）

文件路径：`<target-requirement-dir>/测试报告.md`。

**追加策略**（严格对齐 `../_shared/file-conventions.md` §5 / §5.2）：

- 首次创建：写入一级标题 `# 测试报告 - {编号} - {功能名}`，随后 `## Run 1 - YYYY-MM-DD HH:mm` 起。
- 已存在：**禁止覆盖**；读出当前最大 Run-N，本次以 `## Run {N+1} - YYYY-MM-DD HH:mm` 追加。

每个 Run-N 节至少包含：

```markdown
## Run {N} - YYYY-MM-DD HH:mm

- 测试层级：单元 / 集成 / E2E（标记实际运行的层级）
- 执行环境：{test_backend_stack} / Playwright / 本地
- 运行命令：
  - 单元测试：...
  - 集成测试：...
  - E2E 测试：...
- 用例总数：单元 {a} / 集成 {b} / E2E {c} / 回归 {d}
- 执行结果：通过 {x} / 失败 {y} / 跳过 {z}
- 失败用例清单（按层）：
  - UT/IT/ET-{N} {名称}：失败原因 + 归属（脚本 / 代码 / 改动.md）
- 本轮修正动作：（Step 5 中做了什么修复）
- 结论：全部通过 / 仍有失败（附数量）/ 用户终止
```

### Step 7 — 更新 `_overview.md` 并汇报

**统一协议**：本步骤的"读-改-写"算法严格遵循 [`../_shared/file-conventions.md`](../_shared/file-conventions.md) §10「`_overview.md` 写入算法（统一协议）」；本主 skill 仅作为 §10.3 "触发点"表中 `test-runner` 行的执行者，不重复实现算法逻辑。

- 在 `<requirements_dir>/_overview.md` 中把目标子需求状态从 🟣 测试中 → ✅ 已完成（触发点见 `../_shared/file-conventions.md` §4.2"🟣 → ✅"行）。
- **触发条件**：最近一次 `Run-N` 结论为"全部通过"。若 Step 5 loop 达 max-rounds 仍有失败、或用户终止时仍有失败：状态**保留** 🟣 测试中，在"备注"列写入"测试 Run-{N} 存在失败：{简述}，待人工决策"；允许非线性回退 🟣 → 🟢（见 §4.3）。
- 汇报向用户输出的最小信息：
  - 当前编号 / 功能名
  - 测试层级：单元 / 集成 / E2E（标记本次覆盖了哪些层）
  - 产物绝对路径：`测试.md` / `automation/` / `测试报告.md`
  - 本次 Run-N 结论摘要（通过 / 失败计数 + 关键失败条目）
  - 下一步建议（如"状态已推进到 ✅，可关单" / "请回 `/fullstack` 修复失败用例暴露的代码问题"）

## 子 skill 调用

本 skill **无子 skill**（与 Plan Task 3.1"单文件 skill"一致）。不派发 Agent 子会话；全部步骤在主会话内完成。

## 产出规范

| 产物 | 路径 | 覆盖策略 |
|------|------|---------|
| `测试.md` | `<target-requirement-dir>/测试.md` | 提示覆盖（`_shared/file-conventions.md` §5.1） |
| `automation/unit/*` | `<target-requirement-dir>/automation/unit/` | 按文件提示覆盖；新增脚本不询问 |
| `automation/api/*` | `<target-requirement-dir>/automation/api/` | 按文件提示覆盖；新增脚本不询问 |
| `automation/e2e/*` | `<target-requirement-dir>/automation/e2e/` | 按文件提示覆盖；新增脚本不询问 |
| `测试报告.md` | `<target-requirement-dir>/测试报告.md` | **追加 Run-N**（严禁覆盖；见 `_shared/file-conventions.md` §5.2） |
| `_overview.md` 状态列 | `<requirements_dir>/_overview.md` | 行级更新（🟣 → ✅；或保持 🟣 并写备注） |

所有路径在本 SKILL.md 中**只用语义变量**：`<project_root>` / `<requirements_dir>` / `<target-requirement-dir>` / `<backend_dir>` / `<frontend_dir>` / `<test_dir>`。

## 范围外（本版本不做）

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
| E2E 层 Playwright 未安装 | 在 `<frontend_dir>` 自动安装 `@playwright/test` + `chromium`，ask 用户确认 |
| E2E 层 dev server 启动超时 | 提示用户手动启动 dev server 后重试 |
| Step 5 反复失败 | 区分 脚本问题 / 代码问题 / `改动.md` 不一致 三类归属：前者回 Step 4；中者不改代码、汇报用户回 `/fullstack`；后者回 `change-summarizer` |
| Step 5 达 max-rounds 仍有失败 | **不阻断 Step 6**；`测试报告.md` 如实记录失败 + 归属；状态保留 🟣 + 备注；ask 用户决策 |
| `测试报告.md` 已存在 | **禁止覆盖**；按 `_shared/file-conventions.md` §5.2 读出最大 Run-N 后以 `## Run {N+1}` 追加 |
| `_overview.md` 不存在 | 创建文件写入表头（按 `_shared/file-conventions.md` §3.2），再写当前行 |
| superpowers 未装 | Preflight Step 1 已硬 fail，本流程不会到这里 |

## 禁止事项

- **不硬编码测试框架**：不得在本 SKILL.md 或生成的脚本中写死"用 JUnit / Jest / pytest"；一律引用 Preflight 绑定的 `test_backend_stack`，按"测试框架识别"表映射写法。
- **不跳过 Preflight**，即便用户催促。
- **不擅自回填 `改动.md` 缺失字段**：按 `_shared/requirement-schema.md` §3.2 ask 用户；禁止猜测 / 自动构造默认值。
- **不覆盖 `测试报告.md`**：追加 Run-N，编号严格递增；见 `_shared/file-conventions.md` §5 / §5.2。
- **不在 Step 5 里改被测代码**：脚本暴露的代码问题一律退回 `/fullstack`；本 skill 只修脚本 + `改动.md` 不一致。
- **不硬编码项目名**（如 `shangyunbao-arena` / `asms` / `taikeduo`）或根级目录名（如 `backend` / `frontend` / `test` / `product`）；全部引用 Preflight 绑定的语义变量。
- **不在未识别栈时默默取默认值**：必须 ask 用户（对齐 `project-adapter.md` Part 2.4）。
- **不声称 Run 通过而未看到实际命令输出**：对齐 `fullstack-builder/SKILL.md` Step 4 verification 纪律。
- **不自动 git commit**：本 skill 只落盘 `测试.md` / `automation/*` / `测试报告.md`，并行级更新 `_overview.md`；不执行 `git add` / `git commit` / `git push`。
- **不绕过 Preflight 调用 `superpowers:*`**：所有 superpowers 调用必须在 Preflight 通过后进行。
- **不强行生成 E2E 测试**：当 `frontend_dir` 为 N/A 或 `改动.md` 无前端交互点时，跳过 E2E 层（只写 `无`），不安装 Playwright、不生成空壳脚本。
