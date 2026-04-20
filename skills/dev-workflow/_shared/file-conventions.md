# File Conventions — 子需求目录产物规范

> **定位**：reference 文档，定义单个子需求目录下所有产物的命名、位置、状态流转、覆盖策略。所有主 skill / 子 skill 写入或读取产物时，**必须**对照本文件约定。
>
> **前置**：路径类变量（`<requirements_dir>` 等）来自 [`./project-adapter.md`](./project-adapter.md) Part 4，本文件**不**重复声明路径发现逻辑。

---

## 1 基本结构

### 1.1 目录树

一个子需求的所有产物集中在同一目录：

```
<requirements_dir>/
├── _overview.md                              ← 总览文件（下划线前缀）
└── {编号}-{功能名}/                          ← 单个子需求目录
    ├── PRD.md                  (1) product-designer/prd-writer 产出，面向人
    ├── 需求.md                 (2) product-designer/prd-writer 产出，面向 AI（严格 schema）
    ├── 可行性.md               (3) product-designer/feasibility-assessor 产出
    ├── 改动.md                 (4) fullstack-builder/change-summarizer 产出（对接 test-runner）
    ├── 自审报告.md             (5) fullstack-builder/self-review 产出（多轮追加）
    ├── plan.md                 (6) fullstack-builder 规划阶段产出（由 superpowers:writing-plans 生成）
    ├── 测试.md                 (7) test-runner 产出
    ├── 测试报告.md             (8) test-runner 产出（多次运行追加）
    └── automation/             (9) test-runner 产出的接口自动化脚本目录
        ├── ...
```

### 1.2 九类产物总览

| # | 文件 | 产生者 | 读取方 | 状态 |
|---|------|--------|--------|------|
| 1 | `PRD.md` | prd-writer | 人 / 可行性评估 / 开发 | 需求定稿后稳定 |
| 2 | `需求.md` | prd-writer / requirement-splitter | feasibility-assessor / fullstack-builder / test-runner / self-review | 字段严格结构化 |
| 3 | `可行性.md` | feasibility-assessor | fullstack-builder | 可选但推荐 |
| 4 | `改动.md` | change-summarizer | test-runner | 测试阶段唯一权威输入 |
| 5 | `自审报告.md` | self-review | 人 / 下一轮 self-review | 多轮追加 |
| 6 | `plan.md` | superpowers:writing-plans | executing-plans / TDD 阶段 | 执行过程中更新复选框 |
| 7 | `测试.md` | test-runner | 人 | 测试用例全集 |
| 8 | `测试报告.md` | test-runner | 人 | 多次执行追加 |
| 9 | `automation/` | test-runner | CI / 人 | 独立可运行脚本 |

---

## 2 编号与目录命名规则

> 完整规则见 [`./project-adapter.md`](./project-adapter.md) Part 3.3 / Part 3.4。本节只摘要约束。

- 目录名格式：`{编号}-{功能名}`。
- `{编号}`：由 `next_requirement_id` 给出，缺省正则 `^(\d+)-` max+1。
- `{功能名}`：沿用 `naming_style`（纯中文 / 短横线英文 / 拼音）。
- 编号一经确定，**不得**因后续重排而修改（会破坏引用）。

---

## 3 `_overview.md` 总览文件

### 3.1 位置与命名

- 路径：`<requirements_dir>/_overview.md`
- **下划线前缀是强制的**，原因：
  - `<requirements_dir>` 下的条目要么是文件（`_overview.md`），要么是子需求目录（`{编号}-{功能名}/`）。
  - 子需求目录名以数字开头；若总览文件名以中文或普通英文开头（如 `overview.md` / `总览.md`），按字典序会**混排**在子需求目录中间，既影响人眼扫视也影响 `ls` / 程序枚举。
  - 下划线 `_` 的 ASCII 排序位于大小写字母和数字之前（实际在 `0-9A-Za-z` 之间，但典型工具会把它视为"特殊"），能稳定置顶或分组；更关键的是**下划线前缀本身作为约定**可让 skill 在枚举子需求时直接按"不以下划线开头"过滤排除。
- 其他"目录级元数据"文件同样用 `_` 前缀（如未来可能的 `_config.md`），避免与子需求混淆。

### 3.2 内容约定

- 顶部标题：`# 需求总览`
- 含一个表格列出所有子需求：`| 编号 | 名称 | 状态 | 优先级 | 依赖 | 备注 |`
- 状态用第 4 节定义的表情符流转。
- 每次子需求状态变化时由触发 skill（如 `fullstack-builder` 进入开发时把 🟡 → 🟢）同步更新本文件。

---

## 4 状态流转

### 4.1 标准序列（强制）

```
🔵 待开发  →  🟡 评估中  →  🟢 开发中  →  🟣 测试中  →  ✅ 已完成
```

完整流转：`🔵 待开发` → `🟡 评估中` → `🟢 开发中` → `🟣 测试中` → `✅ 已完成`。

### 4.2 触发点

| 迁移 | 触发 skill | 触发时机 |
|------|-----------|---------|
| (新建) → 🔵 待开发 | `prd-writer` / `requirement-splitter` | 产出 `需求.md` 时 |
| 🔵 → 🟡 | `feasibility-assessor` | 开始评估时 |
| 🟡 → 🟢 | `fullstack-builder` | 进入 plan/TDD 阶段时 |
| 🟢 → 🟣 | `fullstack-builder` | `change-summarizer` 产出 `改动.md` 后 |
| 🟣 → ✅ | `test-runner` | 测试报告判定通过后 |

### 4.3 允许的非线性回退

- 🟢 / 🟣 → 🟡：自审或测试发现需求本身有问题，回到可行性/需求修订。
- 🟣 → 🟢：测试发现代码缺陷，回到开发。
- 回退时必须在 `_overview.md` 的"备注"列记录原因（如"测试发现 AC-3 漏做，回 🟢 补齐"）。

---

## 5 覆盖策略

| 产物 | 策略 | 行为 |
|------|------|------|
| `PRD.md` | **提示覆盖** | 已存在时 ask 用户："覆盖 / 备份后覆盖 / 取消" |
| `需求.md` | **提示覆盖** | 同上（字段严格，合并易错，不做自动合并） |
| `可行性.md` | **提示覆盖** | 评估结果会因代码演化变化，允许重写 |
| `改动.md` | **提示覆盖** | 一次开发一次产出，再次 `fullstack-builder` 时重写 |
| `plan.md` | **提示覆盖** | 同 `改动.md` |
| `测试.md` | **提示覆盖** | 按最新 `改动.md` 重新生成 |
| `自审报告.md` | **追加**（`## Round N` 小节） | 多轮审查累积，**禁止覆盖**，已有内容必须保留 |
| `测试报告.md` | **追加**（`## Run N - {timestamp}` 小节） | 多次执行累积，**禁止覆盖** |
| `automation/*` | **按文件提示覆盖** | 每个脚本独立判断；新增脚本不询问 |

### 5.1 "提示覆盖"的交互模板

```
<文件> 已存在（大小 xxx 字节，最后修改 yyyy-MM-dd）。
请选择：
  【1】覆盖（原文件丢失）
  【2】备份后覆盖（保存为 <文件>.bak-{timestamp}）
  【3】取消本次写入
回复 1 / 2 / 3。
```

### 5.2 "追加"的写入格式

- `自审报告.md`：

  ```markdown
  ## Round 2 - 2026-04-13 15:30

  （本轮自审内容）
  ```

- `测试报告.md`：

  ```markdown
  ## Run 3 - 2026-04-13 16:45

  （本次运行结果）
  ```

- 首次创建时仍需写入标题段（`# 自审报告 - {编号} - {功能名}` / `# 测试报告 - {编号} - {功能名}`），并从 `Round 1` / `Run 1` 开始。

---

## 6 路径表达规约

### 6.1 规定

- 所有 skill 文档、文件模板、提示文本中，**必须**使用以下语义变量引用路径：
  - `<project_root>` / `<project-root>`
  - `<product_dir>` / `<product-dir>`
  - `<requirements_dir>` / `<requirements-dir>`
  - `<backend_dir>` / `<backend-dir>`
  - `<frontend_dir>` / `<frontend-dir>`
  - `<test_dir>` / `<test-dir>`
  - `<target-requirement-dir>`（= `<requirements_dir>/{编号}-{功能名}/`）

### 6.2 禁止

- **禁止**硬编码 `product/`、`backend/`、`frontend/`、`test/` 等根级目录名。
- **禁止**硬编码项目名（如 `shangyunbao-arena` / `asms` / `taikeduo` / `asms/docs/...`）。
- **禁止**在示例中用纯裸相对路径（如 `product/requirements/001-xxx/需求.md`）；必须写作 `<requirements_dir>/001-xxx/需求.md`。

### 6.3 例外

仅在 [`./project-adapter.md`](./project-adapter.md) Part 1/Part 2 的**识别分支**内（即"扫这些候选名"的枚举表里），允许出现裸字符串 `product` / `backend` / `pom.xml` 等——那是扫描的输入字典，不是假设。

---

## 7 automation 子目录约定

### 7.1 位置策略

由 `options.automation_strategy`（config.yml）决定：

| 取值 | 脚本位置 | 适用场景 |
|------|----------|----------|
| `per-requirement`（默认） | `<target-requirement-dir>/automation/` | 脚本与需求强关联；方便追溯 |
| `centralized` | `<test_dir>/{编号}-{功能名}/` | 项目已有统一 test 基建（如 `<test_dir>/conftest.py` / 共享 fixture） |

使用 `centralized` 时，必须在 `<target-requirement-dir>/automation.md` 留一个指针文件，内容 `该需求的自动化脚本位于 <test_dir>/{编号}-{功能名}/`，确保按需求目录追溯仍然可达。

### 7.2 脚本命名

脚本命名遵循 `test_backend_stack` 的惯例：
  - `junit5` → `src/test/java/.../XxxTest.java`（若直接放到 automation/ 下则保留包结构）
  - `pytest` → `test_xxx.py`
  - `jest` / `supertest` → `xxx.test.js` / `xxx.spec.ts`
  - `go-test` → `xxx_test.go`
  - `xunit` / `nunit` → `XxxTests.cs`

### 7.3 可运行性

必须**独立可运行**：由项目现有测试框架驱动；脚本执行目录按 `test_cwd` / `backend_cwd`（见 project-adapter.md Part 4.2）。若项目无测试基建（如空 `<test_dir>`），补最小运行入口（`pom.xml` 子模块 / `package.json` / `pyproject.toml`）并依赖 `<backend_dir>` 产物；本版本不主动为前端补 UI 自动化。

禁止把手工测试清单写入 automation/（手测放 `测试.md` 中）。

---

## 8 N/A 栈短路规则

当 Preflight Step 2 识别出 `backend_stack = N/A` 或 `frontend_stack = N/A`（或等效的 `pending`）时，所有 skill / 子 skill 必须按以下规则跳过相关步骤，而非报错：

### 8.1 `frontend_stack = N/A` / `pending`（纯后端项目或前端待建）

- `feasibility-assessor`：跳过对 `<frontend_dir>` 的 Grep / Read；`涉及文件清单`只含后端文件；`前端交互点` 写 `N/A（纯后端项目）`。
- `fullstack-builder`：plan/TDD 不涉及前端；verification 跳过 `frontend_cwd` 命令；self-review 维度 2 的"前后端契约一致性"退化为"后端内部契约（接口/DTO/事件）一致性"。
- `change-summarizer`：`## 前端交互点` 小节写 `N/A（纯后端改动）`，不删除小节。
- `test-runner`：`test_frontend_stack` 视为 N/A；`测试.md` 的"前端手测清单"写 `N/A`。

### 8.2 `backend_stack = N/A` / `pending`（纯前端项目）

- 对称处理：跳过后端 Grep / verification / 接口契约；`接口变更` 小节在 `改动.md` 中写 `N/A（纯前端项目，无 HTTP 接口变更）`。
- test-runner 仅做前端组件测试。

### 8.3 两者都为 N/A

Preflight Step 3 直接阻断（见 preflight.md §3.2），不会进入主流程。

---

## 9 非 HTTP 改动的自动化策略

某些需求（典型如定时任务、事件驱动、消息监听、邮件/通知发送）的 `改动.md` 中**"接口变更"三节全为 `无`**。此时 `test-runner` 不应产出空壳 `automation/`，而是按"非 HTTP 契约"（见 [`./requirement-schema.md`](./requirement-schema.md) 改动.md §"非 HTTP 契约字段"）生成以下自动化：

| 改动类别 | 推荐自动化策略 | 典型实现 |
|----------|---------------|---------|
| **定时任务** | 集成测试 + 手动触发 Scheduled Bean | Spring：`@SpringBootTest` + 注入 bean 手工调方法；Node：把 cron handler 抽成纯函数直测 |
| **事件监听** | 事件发布 + 监听器调用断言 | Spring：`ApplicationEventPublisher.publishEvent` + `@MockBean` 断言被调；Node：EventEmitter `emit` + spy |
| **消息通道** | MQ 生产者 / 消费者独立测试 | 生产者：断言发送内容 + routing key；消费者：模拟收到消息，断言业务动作 |
| **邮件 / 通知通道** | MailService / 通知 SDK Mock + 模板渲染断言 | Spring：`@MockBean JavaMailSender`；Node：Mock nodemailer；渲染模板内容做 snapshot |

`test-runner` 遇到"接口变更"三节为空但有上述其一 / 多类变更时：
1. 产出对应测试用例到 `测试.md`（功能测试 / 集成测试）。
2. 产出对应自动化脚本到 `automation/`。
3. 在 `测试报告.md` 首条标注"本需求无 HTTP 接口改动，采用非 HTTP 自动化策略"。

---

## 10 `_overview.md` 写入算法（统一协议）

**所有主 skill** 在更新 `<requirements_dir>/_overview.md` 时**必须**遵循本算法，避免多套主 skill 各自实现导致格式漂移和并发冲突。

### 10.1 输入：写入意图（结构化数据）

主 skill 接收来自子 skill 的回传，或自己生成更新意图：

```yaml
overview_update:
  action: append | update | bulk_init
  rows:
    - id: "<编号>"
      name: "<功能名>"             # 仅 append / bulk_init 必填
      status: "<状态符>"           # 状态符必须是 §4.1 五个之一
      priority: "<P0|P1|P2>"       # 仅 append / bulk_init 必填
      depends_on: "<编号列表 或 无>"  # 仅 append / bulk_init 必填
      note: "<备注 或 —>"
```

### 10.2 算法（读-改-写）

```
1. Read <requirements_dir>/_overview.md
   - 文件不存在 → 创建并写入表头：
       # 需求总览
       
       | 编号 | 名称 | 状态 | 优先级 | 依赖 | 备注 |
       |------|------|------|--------|------|------|
   - 文件存在但表头格式异常 → 按 §5 走"提示覆盖 / 备份后覆盖 / 取消"
2. 按 action 处理 rows：
   - append   ：追加新行；编号已存在则改用 update
   - update   ：定位 编号 列匹配的行，原地修改其他列；行不存在则改用 append
   - bulk_init：整批 rows；与现有合并（按子 skill 返回的合并策略：覆盖 / 合并 / 跳过）
3. 排序：按 编号 升序（保证多次写入后顺序稳定）
4. 写回 <requirements_dir>/_overview.md
```

### 10.3 各主 skill 的触发点

| 主 skill | 触发时机 | action | 状态变化 |
|----------|---------|--------|---------|
| `product-designer`（prd-writer 完成后） | 子 skill 回传 | append | 新增 → 🔵 待开发 |
| `product-designer`（requirement-splitter 完成后） | 子 skill 回传 | bulk_init | 新增 → 🔵 待开发 |
| `product-designer`（feasibility-assessor 完成后） | 子 skill 回传 | update | 🔵 → 🟡 评估中 |
| `fullstack-builder`（Step 7） | 主 skill 自发 | update | 🟡 / 🔵 → 🟢 开发中（进入开发时） / 🟢 → 🟣 测试中（Step 6 成功后） |
| `test-runner`（Step 7） | 主 skill 自发 | update | 🟣 → ✅ 已完成（Run-N 全部通过时） |

### 10.4 失败处理

- **文件锁竞态**（极少；同一 git 仓库下顺序执行不应发生）：写入前 Read 一次校验最近修改时间未变，否则重读再写。
- **行号偏移**（手工编辑过 `_overview.md`）：按"编号"列定位，**不**按行号；编号不存在则按 action 兜底。
- **格式异常**：`_overview.md` 表头列数与本节定义不一致时，按 §5 走"提示覆盖 / 备份后覆盖 / 取消"。

### 10.5 禁止

- **子 skill 不得直接写 `_overview.md`**：只能回传 `overview_update` 给主 skill。
- **主 skill 之间不得交叉写**：每个主 skill 只更新本流程触发点对应的状态。
- **不得越过 §4.1 五状态符**或 §4.2 触发点表。

---

## 禁止事项

- **不得在 skill 文档中硬编码根级目录名**（见 6.2）。
- **不得覆盖追加类文件**（`自审报告.md` / `测试报告.md`）。
- **不得省略 `_overview.md` 的下划线前缀**。
- **不得**跳过状态流转更新（每次子需求状态变化必须同步写回 `_overview.md`）。
- **不得**用非标准状态符号（必须使用第 4.1 节五个表情符之一）。
