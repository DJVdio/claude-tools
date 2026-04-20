# Project Adapter — 路径 / 技术栈 / 约定 运行时学习

> **定位**：reference 文档，被 [`./preflight.md`](./preflight.md) Step 2 调用。承担所有"项目自适应"职责：不硬编码项目名、路径、技术栈。
>
> **执行路径**：主 skill 在 Preflight Step 2 Read 本文件后，按 Part 1 → Part 2 → Part 3 → Part 4 顺序执行并绑定下游变量。

---

## Part 1 — 路径发现（三级优先级）

所有路径必须**仅在本 Part 内确定**，下游 skill 只使用 Part 4 绑定的变量。

### 优先级 1：显式配置

读取 `<project-root>/.claude/skills/config.yml`（其中 `<project-root>` 即当前 git 仓库 / 工作目录根）。

完整示例见 `../config.example.yml`；关键节如下：

```yaml
paths:
  product: <auto-detect>       # 产品文档目录（可写相对路径，或 N/A）
  frontend: <auto-detect>      # 前端代码目录
  backend: <auto-detect>       # 后端代码目录
  test: <auto-detect>          # 测试根目录（可与 backend/frontend 内嵌冲突，取最具体）
  requirements: <auto-detect>  # 子需求聚合目录
stack:
  backend: <auto-detect>
  frontend: <auto-detect>
  test-backend: <auto-detect>
  test-frontend: <auto-detect>
options:
  self-review-max-rounds: 3       # fullstack-builder self-review loop 最大轮次
  test-fix-max-rounds: 3          # test-runner 修复 loop 最大轮次
  feasibility-read-max-files: 5   # feasibility-assessor 读文件上限
  automation_strategy: per-requirement  # 或 centralized
```

若 `config.yml` 存在且包含 `paths.<key>` 且其值不为 `<auto-detect>` / `null`，则该路径直接采用，**不进入优先级 2**。逐键判定：任一 key 缺失或占位 → 该 key 进入优先级 2。

### 优先级 2：常见命名扫描

对 `<project-root>` 根目录执行扫描，按下列优先顺序匹配。**monorepo 项目**优先扫 `apps/*` / `packages/*` / `services/*` 下的子包。

| 变量 | 候选目录（按顺序匹配第一个存在的） |
|------|------------------------------------|
| `product_dir` | `product/`、`prd/`、`specs/`、`design/`、`product-docs/`、`docs/product/`、`docs/prd/`、`docs/specs/`、`docs/`（最后兜底） |
| `requirements_dir` | `<product_dir>/requirements/`、`<product_dir>/specs/`、`<product_dir>/features/`、`<product_dir>/prd/`、`<product_dir>/docs/`、`requirements/` |
| `backend_dir` | `backend/`、`server/`、`api/`、`service/`、`apps/server/`、`apps/api/`、`apps/backend/`、`packages/server/`、`packages/api/`、`services/api/`、`src/Server/`、`src/Api/`、`src/Backend/`（.NET 惯例 `src/<ProjectName>/`）、`cmd/`、`internal/`、`src/`（单仓兜底） |
| `frontend_dir` | `frontend/`、`web/`、`client/`、`ui/`、`site/`、`apps/web/`、`apps/frontend/`、`apps/client/`、`apps/dashboard/`、`packages/web/`、`packages/client/`、`src/Web/`、`src/Client/`、`src/UI/`、`app/`（单仓兜底） |
| `test_dir` | `test/`、`tests/`、`qa/`、`e2e/`、`spec/`、`integration/`、`it/`、`__tests__/`、`testing/`、`<backend_dir>/src/test/`、`<frontend_dir>/tests/`、`<frontend_dir>/__tests__/` |

扫描规则：
- 目录存在即命中；匹配第一个即停。
- `product_dir` 候选顺序把 `prd/` / `specs/` 提到 `docs/` 之前：`docs/` 抢占风险高，很多项目 `docs/` 是全量文档而非需求集。
- `requirements_dir` 若不存在但 `product_dir` 存在，允许在 `product_dir` 下新建 `requirements/` 子目录（但**必须**进入优先级 3 向用户确认）。
- **monorepo 识别**：若根目录存在以下任一标志文件，在扫描 `backend_dir` / `frontend_dir` 时**优先**扫 `apps/*` / `packages/*` / `services/*` / `src/*` 下的子包；可命中多个 → ask 用户选择主 backend / 主 frontend：
  - **JS/TS 生态**：`pnpm-workspace.yaml` / `lerna.json` / `nx.json` / `turbo.json` / `rush.json`
  - **.NET**：`*.sln`（解决方案文件，子项目通常在 `src/<ProjectName>/`）
  - **Rust**：`Cargo.toml` 含 `[workspace]` 节
  - **Go**：`go.work`（多模块工作区）
  - **Gradle**：`settings.gradle` / `settings.gradle.kts` 含 `include` 子项目声明

### 优先级 3：ask 用户

优先级 1 + 优先级 2 后仍未绑定的 key，**必须**交互询问用户，**不得默默取默认值**。话术模板：

```
未能自动识别 <key>（如 `backend_dir`）。请提供相对于项目根的相对路径；
或回复 "N/A" 表示本项目无此目录（如纯前端项目无 backend）。
是否把你提供的路径写入 `.claude/skills/config.yml` 持久化？（y/n）
```

**`requirements_dir` 专用话术**（当 `<product_dir>/requirements/` 不存在但 `product_dir` 已绑定）：

```
检测到 <product_dir>/requirements/ 不存在。
是否在 <product_dir>/ 下创建 requirements/ 子目录作为子需求聚合根？
  【1】是，创建并绑定（推荐；同时写入 config.yml 持久化）
  【2】是，创建但不写入 config.yml（仅本会话有效）
  【3】否，由我手动指定其他路径
回复 1 / 2 / 3。
```

---

## Part 2 — 技术栈识别

### 2.1 后端标志文件映射

按下列映射表扫描 `<backend_dir>`（或 `<project-root>`，单仓时）：

| 标志文件 | `backend_stack` 取值 | 额外判定 |
|----------|----------------------|----------|
| `pom.xml` | `java-maven` | 含 `spring-boot-starter-parent` / `spring-cloud-*` → `java-spring` |
| `build.gradle` / `build.gradle.kts` | `java-gradle` / `kotlin-gradle` | 含 `spring-boot-starter` → `java-spring-gradle` / `kotlin-spring` |
| `package.json` + deps 含 `express` / `koa` / `fastify` | `node-express` / `node-koa` / `node-fastify` | — |
| `package.json` + deps 含 `@nestjs/core` | `node-nest` | — |
| `requirements.txt` / `pyproject.toml` | `python` | 含 `fastapi` → `python-fastapi`；`django` → `python-django`；`flask` → `python-flask` |
| `go.mod` | `go` | 读 import 识别 `gin` / `echo` / `fiber` → `go-gin` 等 |
| `Cargo.toml` | `rust` | 含 `actix-web` / `axum` / `rocket` → `rust-actix` 等 |
| `*.csproj` / `*.sln` + `dotnet` | `dotnet` | 含 `Microsoft.AspNetCore` → `dotnet-aspnet` |
| `Gemfile` | `ruby` | 含 `rails` → `ruby-rails`；`sinatra` → `ruby-sinatra` |
| `composer.json` | `php` | 含 `laravel/framework` → `php-laravel`；`symfony/*` → `php-symfony`；`slim/slim` → `php-slim` |
| `mix.exs` | `elixir` | 含 `phoenix` → `elixir-phoenix` |
| `build.sbt` | `scala` | 含 `play` → `scala-play`；`akka-http` → `scala-akka` |
| `deno.json` / `deno.jsonc` | `deno` | — |
| `bun.lockb` + `package.json` | `bun` | 含 `elysia` → `bun-elysia` |

**多个标志同时命中**：列出所有命中，ask 用户确认主后端。

### 2.2 前端标志文件映射

扫描 `<frontend_dir>/package.json`（或单仓根 `package.json`）`dependencies` + `devDependencies`：

| 关键依赖 | `frontend_stack` 取值 | 额外判定 |
|---------|------------------------|---------|
| `vue` | `vue` | + `typescript` → `vue-ts`；含 `nuxt` → `nuxt` |
| `react` | `react` | + `typescript` → `react-ts` |
| `next` | `next` | 优先级高于 `react` |
| `remix` / `@remix-run/*` | `remix` | 与 `next` 同级 |
| `svelte` | `svelte` | + `@sveltejs/kit` → `sveltekit` |
| `@angular/core` | `angular` | — |
| `solid-js` | `solid` | + `solid-start` → `solid-start` |
| `@builder.io/qwik` | `qwik` | — |
| `astro` | `astro` | — |
| `preact` | `preact` | — |

**优先级**：`next` > `react`；`remix` > `react`；`nuxt` > `vue`；`sveltekit` > `svelte`；`solid-start` > `solid`。

### 2.3 测试栈识别（**独立识别，允许与后端栈异构**）

**关键变更**：不再完全绑定到后端栈推导。改为"先扫 `<test_dir>` 实际内容，再 fallback 后端栈默认"。

#### 2.3.1 扫描 `<test_dir>` 内测试文件后缀统计

列出 `<test_dir>` 下所有文件，按后缀名特征分类：

| 文件名特征 | 命中 `test_backend_stack` |
|------------|---------------------------|
| `*Test.java` / `*IT.java` | `junit5+restassured`（默认）或 `junit5+springtest`（若读到 `@SpringBootTest`） |
| `*.test.ts` / `*.test.js` / `*.spec.ts` / `*.spec.js` | `jest+supertest` 或 `vitest+supertest`（看 `<backend_dir>/package.json` 里 `jest` vs `vitest`） |
| `test_*.py` / `*_test.py` | `pytest+httpx` / `pytest+requests`（按 import 判定）/ `pytest+respx`（async） |
| `*_test.go` | `go-test` |
| `*_test.rs` 或 `tests/` 目录（Rust 惯例） | `cargo-test` |
| `*_test.cs` / `*Test.cs` | `xunit` / `nunit` / `mstest`（按 csproj 的 `PackageReference` 区分：含 `xunit.core` → `xunit`；含 `NUnit` → `nunit`；含 `MSTest.TestAdapter` → `mstest`） |
| `*_spec.rb` / `*_test.rb` | `rspec+rack-test`（Ruby） |
| `*Test.php` | `phpunit+laravel-test`（若项目是 Laravel）/ `phpunit` |
| `*_test.exs` | `exunit` |
| `*Spec.scala` / `*Test.scala` | `scalatest` |

**命中规则**：统计各类文件数量，取**最多的那一类**作为 `test_backend_stack`。若并列或模糊（如单文件），回退 2.3.2。

#### 2.3.2 后端栈推导（fallback）

当 `<test_dir>` 为空或无显著特征时，按后端栈推导：

| 后端栈 | `test_backend_stack` 默认 |
|---------|---------------------------|
| `java-*` | `junit5+restassured` |
| `node-*` | `jest+supertest`（含 `jest` 依赖）/ `vitest+supertest`（含 `vitest` 依赖）/ `mocha+chai+supertest`（老项目含 `mocha`） |
| `python-*` | `pytest+httpx` / `pytest+requests` |
| `go` | `go-test` |
| `rust` | `cargo-test` |
| `dotnet*` | `xunit` / `nunit`（按 csproj 引用） |
| `ruby-*` | `rspec+rack-test` |
| `php-*` | `phpunit` |
| `elixir-phoenix` | `exunit` |
| `scala-*` | `scalatest` |

#### 2.3.3 前端测试栈

| 前端栈 | `test_frontend_stack` 默认 | 附加识别 |
|---------|-----------------------------|----------|
| `vue-*` / `nuxt` | `vitest` | + `@testing-library/vue` → `vitest+testing-library` |
| `react*` / `next` / `remix` | `jest` 或 `vitest`（看 package.json） | + `@testing-library/react` → `<stack>+testing-library` |
| `svelte*` | `vitest` | — |
| `angular` | `karma+jasmine` 或 `jest` | 读 `angular.json` 的 `projects.<name>.architect.test.builder`：`@angular-devkit/build-angular:karma` → `karma+jasmine`；`@angular-builders/jest:run` 或包含 `jest` → `jest` |
| `solid*` | `vitest` | — |
| 其他 | ask | — |

### 2.4 未识别时

任一 stack 未识别（0 个标志命中）→ **不得默默取默认值**，ask 用户：

```
未能自动识别 <backend_stack / frontend_stack / test_*_stack>。
请回复栈标识（如 java-spring / node-nest / python-fastapi / N/A）。
可选择写入 config.yml 持久化。
```

**目录存在但无标志文件**（常见于"已创建占位但尚未开发"的目录，如空的 `frontend/`）：绑定该 stack 为 `pending`（等同 N/A，但标注"目录存在但待建设"），不阻塞主流程，下游 skill 按 `N/A` 短路。

### 2.5 verification 执行目录（cwd）

verification 命令（如 `mvn test` / `npm test` / `pytest`）的**执行目录**必须对齐栈归属的代码目录，避免 monorepo 根目录跑错脚本。

| 栈类别 | 默认 cwd | 备注 |
|--------|----------|------|
| `backend_stack` 非 N/A | `<backend_dir>` | 后端 verification 命令全部在此执行 |
| `frontend_stack` 非 N/A | `<frontend_dir>` | 前端 verification 命令全部在此执行 |
| `test_backend_stack` 异构目录（如后端 Node + test 在 pytest 独立目录） | `<test_dir>` | 当 2.3.1 命中与 2.3.2 推导不一致时使用 |

用户可用 `config.yml` 的 `paths.*` 配合 `stack.*_cwd` 覆盖（未定义则按默认）。

---

## Part 3 — 项目约定学习

### 3.1 代码规范文档

按下列顺序尝试 Read（存在则读入内存绑定到 `code_conventions`）：

1. `<project-root>/CLAUDE.md`
2. `<project-root>/AGENTS.md`
3. `<project-root>/.cursorrules`
4. `<backend_dir>/CLAUDE.md`（若存在子 CLAUDE.md）
5. `<frontend_dir>/CLAUDE.md`

多个存在时 **全部读取**，在 `code_conventions` 下分键保存（`root` / `backend` / `frontend` / ...）。

### 3.2 需求文档模板学习（2~3 个样例）

- 目标：学习 `<requirements_dir>` 下已有需求文档的结构，为后续生成新需求提供"与项目风格一致"的参考。
- 操作：
  1. 列出 `<requirements_dir>/` 下的子目录与文件。
  2. 选 **2 ~ 3 个** 样例（数量必须 ≥ 2，避免"偶然样本"导致学错风格），优先取编号靠前且完整的目录。
  3. Read 每个样例中的 `需求.md`（或项目已有的等价文件），提取：
     - 章节标题序列
     - 字段命名（中英、大小写）
     - 编号前缀风格（如 `FP-1` vs `F1`）
     - 验收标准表达风格（`- [ ] AC-1` vs 表格 vs 其他）
- 样例不足 2 个时（新项目）：跳过学习，提示"首个需求将直接采用 [`./requirement-schema.md`](./requirement-schema.md) 默认 schema"。

### 3.3 编号规则扫描

- **默认规则**：扫 `<requirements_dir>/*` 目录名，正则 `^(\d+)-` 捕获编号，取 **max + 1** 为 `next_requirement_id`。
- **非数字编号特殊处理**：若现有目录名前缀不是纯数字（例如 `REQ-001-xxx` / `feat-xxx` / 纯中文），则：
  - 尝试扩展正则到 `^([A-Z]+-)?(\d+)-` 并保留前缀。
  - 完全无数字部分时（如 `feat-login` / `需求一-xxx`），**不**强行赋数字编号，ask 用户现行编号体系并给建议（"建议启用 `NNN-` 数字编号以便稳定排序"）。
- **空目录**（无任何历史需求）：`next_requirement_id = 1`（或按用户指定的起始编号，如 `001` / `100`）。

### 3.4 目录命名风格学习

从 3.2 的样例中提取 `{编号}-{功能名}` 中 `{功能名}` 的风格：
- 纯中文（如 `001-用户登录`）
- 短横线分隔英文（如 `001-user-login`）
- 拼音 / 混合

绑定到 `naming_style`，后续生成新目录名时沿用相同风格。

**空项目兜底**：样例不足 2 个无法提取时：
1. 从 `code_conventions.root` / `code_conventions.backend` / `code_conventions.frontend` 任一处查找"中文文档"/"英文文档"的规约。例如 CLAUDE.md 写"所有文档和注释使用中文"→ 推断 `naming_style = 纯中文`；写"English only"→ `short-dash-english`。
2. 推断不出时 **ask 用户**，不得默默选择。

---

## Part 4 — 下游可用变量清单

本 Part 是对 Preflight Step 2 结束后、下游所有 skill / 子 skill 可直接引用的变量的**完整枚举**。下游 skill 编写时只使用这些变量名，不自己重新探测。

### 4.1 路径类（项目级）

| 变量 | 含义 | 可能取值示例 | 缺失处理 |
|------|------|-------------|----------|
| `project_root` | 项目根绝对路径 | `/Users/xxx/my-project` | 不可缺失（Preflight 进入即确定） |
| `product_dir` | 产品文档目录 | `<project_root>/product` | Part 1 保证已绑定，可为 `N/A` |
| `requirements_dir` | 子需求聚合目录 | `<product_dir>/requirements` | 必须存在或可创建 |
| `backend_dir` | 后端代码目录 | `<project_root>/backend` | 纯前端项目为 `N/A` |
| `frontend_dir` | 前端代码目录 | `<project_root>/frontend` | 纯后端项目为 `N/A` |
| `test_dir` | 测试根目录 | `<project_root>/test` | 可为 `N/A`（按 backend/frontend 内嵌 test） |

### 4.2 技术栈类

| 变量 | 含义 | 取值示例 |
|------|------|---------|
| `backend_stack` | 后端主栈 | `java-spring` / `node-nest` / `python-fastapi` / `go-gin` / `rust-actix` / `dotnet-aspnet` / `ruby-rails` / `php-laravel` / `elixir-phoenix` / `scala-play` / `kotlin-spring` / `deno` / `bun-elysia` / `N/A` / `pending` |
| `frontend_stack` | 前端主栈 | `vue-ts` / `react-ts` / `next` / `remix` / `sveltekit` / `angular` / `solid` / `qwik` / `astro` / `preact` / `N/A` / `pending` |
| `test_backend_stack` | 后端测试栈 | `junit5+restassured` / `jest+supertest` / `vitest+supertest` / `pytest+httpx` / `pytest+requests` / `pytest+respx` / `go-test` / `cargo-test` / `xunit` / `nunit` / `rspec+rack-test` / `phpunit` / `exunit` / `scalatest` / `mocha+chai+supertest` |
| `test_frontend_stack` | 前端测试栈 | `vitest` / `jest` / `karma+jasmine`（可附加 `+testing-library`） |
| `backend_cwd` | 后端 verification 执行目录 | 默认 `<backend_dir>` |
| `frontend_cwd` | 前端 verification 执行目录 | 默认 `<frontend_dir>` |
| `test_cwd` | 测试执行目录 | 异构测试场景下非默认 |

### 4.3 约定与规则类

| 变量 | 含义 | 来源 |
|------|------|------|
| `code_conventions` | 代码规范（多文件合并） | Part 3.1 |
| `naming_style` | 子需求目录命名风格 | Part 3.4 |
| `next_requirement_id` | 下一个可用子需求编号 | Part 3.3 |
| `requirement_template_samples` | 2~3 个已学样例的结构摘要 | Part 3.2 |

### 4.4 状态类

| 变量 | 含义 |
|------|------|
| `superpowers_available` | Preflight Step 1 产出；硬依赖模式下始终为 `true`（否则 Preflight 直接硬 fail） |

### 4.5 会话级变量（每次主 skill 触发新建）

| 变量 | 含义 | 绑定点 |
|------|------|--------|
| `session_base` | 当次 skill 会话开始时的 git HEAD commit hash | Preflight Step 2.5（`git rev-parse HEAD`），失败时 `<empty>` |
| `<target-requirement-dir>` | 本次主流程对应的子需求目录（`<requirements_dir>/{编号}-{功能名}/`） | Preflight Step 3.0 推断算法绑定 |

**会话级变量贯穿本次主 skill 执行的所有步骤和派发的 subagent**：
- `session_base` 下游所有 `git diff` **必须**用 `git diff <session_base>`，不得用 `git diff HEAD`。
- `<target-requirement-dir>` 是本次主 skill 的"工作目录"；子 skill 派发上下文必须包含其绝对路径。

---

## 失败处理约定

- **不默默取默认值**：Part 1 / Part 2 / Part 3 任何步骤未能确定值时，必须 ask 用户。
- **写 config.yml 需用户同意**：自动探测得到的值只在当前会话有效；用户确认后才写入 `config.yml` 持久化。
- **冲突时以用户回答为准**：config.yml 值与当前扫描结果冲突时，优先 config.yml，但如用户主动指示以扫描为准则改用扫描值并询问是否更新 config.yml。
- **N/A 是合法值**：允许某些路径/栈为 `N/A`（如纯前端项目无 backend），下游 skill 见到 `N/A` 应跳过相关步骤而非报错。引用 [`./file-conventions.md`](./file-conventions.md) 的"N/A 栈短路规则"。
- **pending 与 N/A 等效**：目录存在但无标志文件时绑定 `pending`，下游同 N/A 处理。

---

## 数据库迁移识别（供 change-summarizer 引用）

迁移脚本识别**按文件名特征**而非硬编码路径：

| 特征 | 机制 | 常见路径 |
|------|------|----------|
| 文件名符合 `V\d+__.*\.sql` | flyway | `src/main/resources/db/migration/`（Java/Maven）/ `migrations/`（Node/Python flyway-plugin）/ `db/migration/` |
| 文件名符合 `\d+_.*\.sql` + `changelog.xml` 同级 | liquibase | `src/main/resources/db/changelog/` / `db/changelog/` |
| `migrations/` 目录 + JS/TS 文件含 `up` / `down` exports | `knex` / `sequelize-cli` / `typeorm` | Node 项目 `migrations/` / `db/migrations/` / `src/migrations/` |
| `prisma/migrations/` 目录 + `migration.sql` | `prisma` | `prisma/migrations/` |
| `drizzle/` 目录 + `meta/_journal.json` | `drizzle-kit` | `drizzle/` |
| `Migrations/*.Designer.cs` + `*ModelSnapshot.cs` | EF Core (.NET) | `<project>/Migrations/` |
| `db/migrate/<timestamp>_*.rb` | Rails ActiveRecord | `db/migrate/` |
| `<app>/migrations/<NNNN>_*.py` + `__init__.py` | Django migrations | `<app>/migrations/` |
| `alembic/versions/*.py` + `alembic.ini` | Alembic (Python) | `alembic/versions/` |
| `database/migrations/<timestamp>_*.php` | Laravel | `database/migrations/` |
| `priv/repo/migrations/<timestamp>_*.exs` | Phoenix Ecto (Elixir) | `priv/repo/migrations/` |
| 其他手写 SQL 迁移 | 兜底：列出所有 `*.sql` 文件 + ask | — |

下游 skill 使用时：Grep 上述特征 → 命中即按该机制分类 → 找不到则按"手写 SQL"兜底 + ask 用户确认。

---

## 禁止事项

- **不得硬编码项目名**（如 `shangyunbao-arena` / `asms` / `taikeduo`）。本文件所有路径均用 `<project_root>`、`<backend_dir>` 等语义变量。
- **不得硬编码技术栈假设**。识别分支内出现 `pom.xml` / `package.json` 等是允许的；但"主流程"级别不得假设任何栈。
- **不得跳过 ask**：优先级 3 是兜底而非可选。
- **不得在下游 skill 中重新实现路径/栈判断**：下游只读 Part 4 的变量。
- **不得假设测试栈与后端栈一致**：Part 2.3.1 优先。
