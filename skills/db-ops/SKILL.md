---
name: db-ops
description: Safely execute database operations on the project's MySQL DB. Connects to TEST DB directly, renders SQL text for PROD (via DMS / Bytebase / DBA tool — configured per project). Use whenever the user asks to query, inspect, modify, insert, update, delete, or otherwise operate on the project database — in any phrasing like "查测试库", "改一下 sys_menu", "删掉工单", "给我一个正式库的 SQL", etc. ALWAYS go through this skill instead of running mysql / raw SQL directly.
---

# db-ops

交互式数据库操作 skill。严格三步流程,高危操作带风险分析与确认。

## 绝对规则(不得违反)

1. **三步流程,禁止跳步。** 每次调用必须走步骤 1 → 2 → 3。永远不能跳过步骤 1,永远不能根据上下文推断环境。
2. **正式服永不直连。** 正式服只输出 SQL 文本给用户复制到执行工具(DMS/Bytebase/DBA 流程,看 config 配置)。
3. **用户中途改 SQL 或意图,必须回到步骤 2 重新开始。** 不允许在当前上下文私自调整 SQL 后继续执行。
4. **所有展示的中文环境 banner 严格按本文件模板,不要改措辞或 emoji。**
5. **跨调用绝不复用 ENV。** 即使前一轮选过 TEST,本轮必须重走步骤 1。

## 路径约定

下文所有命令里的 `<SKILL_DIR>` 指本 SKILL.md 所在目录。Claude 通常通过 Skill 工具激活时已知该目录,典型值是 `~/.claude/skills/db-ops/` 或 `<project-root>/.claude/skills/db-ops/`。如果不确定,用 `python3 -c "import pathlib; print(pathlib.Path('~/.claude/skills/db-ops').expanduser())"` 取一次。

## 配置(可选)

如果 `<SKILL_DIR>/config.yml` 存在,db_ops.py 优先读取它(支持配置 TEST 连接来源、PROD 执行工具名、audit log 路径等)。如果不存在,自动回退到旧行为(读 asms 项目的 application-test.yaml)。详见 `<SKILL_DIR>/config.example.yml`。

跨项目复用步骤:
1. `cp -r ~/.claude/skills/db-ops <new-project>/.claude/skills/`
2. `cp config.example.yml config.yml` 并改 environments 块
3. `pip3 install -r requirements.txt`
4. `python3 db_ops.py self-check` 验证连接通过

## Audit log

每次 analyze / exec-test / exec-test-critical / render-prod 调用都会在 `<SKILL_DIR>/audit.log`(可被 `options.audit_log_path` 覆盖)追加一行,tab 分隔。包括两类被拒事件(CRITICAL 路由错误、phrase mismatch),便于事后追溯安全事件。

行格式:
```
<时间戳>\t<env>\t<level>\t<sql_hash>\t<result_summary>\t<sql_first_120>
```

字段含义:
- `时间戳` — `YYYY-MM-DD HH:MM:SS`(本地时区)
- `env` — `test` / `prod`
- `level` — `LOW / MEDIUM / HIGH / CRITICAL / INVALID`
- `sql_hash` — SQL 全文 SHA256 前 12 字符,用于跨日志关联同一条 SQL
- `result_summary` — 简短结果(如 `analyze level=HIGH` / `exec-test affected=3 rows=0 ms=12` / `exec-test REJECTED: CRITICAL routed to wrong subcommand`)
- `sql_first_120` — SQL 压平为单行后的前 120 字符(超出截断)

无文件锁,并发追加可能行序错乱(可接受)。无大小上限,长期跑需要外部 logrotate。

## 依赖检查(首次使用)

调用前先跑:
```bash
python3 -c "import pymysql, yaml, sqlparse" 2>&1
```
任一 import 失败,询问用户:
> 缺少依赖 (pymysql/pyyaml/sqlparse),是否运行 `pip3 install -r <SKILL_DIR>/requirements.txt`?

用户同意后执行;不同意则中止整个 skill。

## 步骤 0 — 上下文清零(每次激活必跑)

激活本 skill 的每一次新 prompt 都视为**全新调用**。在做任何事之前:

- **不**读上一轮 ENV、不读上一轮 SQL、不读上一轮快捷锁定记录
- **不**因为"看起来用户还在 db-ops 流程中"就跳过步骤 1
- 即使用户连续发问("再帮我查 sys_dict"),也必须重打步骤 1

这是绝对规则 5("跨调用绝不复用 ENV")的执行方式。LLM 的天性是从对话历史推断当前状态,这条规则是反人性约束,必须显式压制。

## 步骤 1 — 环境选择

### 1.0 快捷锁定 TEST(仅 TEST 可跳过确认)

若用户**首条调用 skill 的原文**里明确包含以下任一关键词,**直接把 `ENV` 锁为 test,跳过 1.1 环境选择块,进入步骤 2**:
- `测试服` / `测试库` / `测试环境` / `test 库` / `test 环境` / `TEST` / `🧪`

跳过时,在步骤 2 的环境行**额外加一句**:`(根据你的原文 "<关键词>" 自动锁定)`,让用户看到为什么跳过。

**绝对禁止**(这是 LLM 防御性二次确认本能的常见违反点):
- ❌ 打印任何形式的环境选择 banner(完整 1.1 块、简化 ASCII 框、纯文本"默认测试服,确认?")
- ❌ 打印"等确认"/"等你回复"/"默认 1,确认下"等任何要求用户回话的措辞
- ❌ 用"默认 X"暗示用户可以否决

命中关键词 = **跳过一切环境交互,直奔步骤 2 的"环境已锁定: 🧪 TEST"那一行**。用户既然写了"测试服",就是已经表态了,任何二次确认都是浪费一轮对话。

正确示例(命中"测试服"关键词):
```
环境已锁定: 🧪 TEST  (根据你的原文 "测试服" 自动锁定)

请描述你要做什么?(自然语言或直接贴 SQL 都可以)
```

错误示例(违反 1.0):
```
请选择目标环境:
  [1] 🧪 测试服 (...)
  [2] 🔥 正式服 (...)
默认 1 测试服,等确认。     ← 命中"测试服"还问,这是反模式
```

**关键词必须是完整词形**:
- 接受:`查一下测试库`、`TEST 环境改一下`、`🧪 跑个 select`
- **不接受**(走 1.1):`a/b test 一下`、`小写 test 没带"库/环境"后缀的孤立词`、`testing` 含 test 子串
- 大写孤立 `TEST`(全大写,前后非字母)接受;小写 `test` 必须带 `库/环境` 后缀

**正式服绝不适用快捷**。即使用户写了"正式服"/"正式库"/"生产服"/"prod"/"PROD"/"DMS",也必须走 1.1 完整确认流程(PROD 操作成本更高,不允许免确认)。

**有歧义时不走快捷**。若原文同时出现"测试"和"正式",或出现否定式("别在测试库里"),一律走 1.1。

### 1.1 完整环境选择(未命中快捷,或用户提到 PROD)

环境信息(label / 连接地址)由 db_ops.py 从 config 读取。Claude 输出 banner 时如果没有 config 元数据,使用以下兜底模板;如果需要精确显示当前 config 下的连接地址,先跑 `python3 <SKILL_DIR>/db_ops.py self-check` 取 environments 列表与 test_connection 状态,再根据 config.yml 的 `environments.test.label` / `environments.prod.label` 替换下面的 emoji 与括号说明。

兜底模板(适用于没有 config.yml 的旧 asms 场景):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请选择目标环境:
  [1] 🧪 测试服 (config.yml 未配置时回退到 asms application-test.yaml)
  [2] 🔥 正式服 (DMS, 仅生成 SQL)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

接受的回复:`1` / `2` / `测试` / `正式` / `test` / `prod`。其他一律视为无效,原样重新打印这个块,不要自己猜。

选中后设置内部变量 `ENV` ∈ `{test, prod}`,进入步骤 2。

## 步骤 2 — 询问意图并生成 SQL

根据 `ENV` 打印:

- test:`环境已锁定: 🧪 TEST`
- prod:`环境已锁定: 🔥 PROD`

(若是从 1.0 快捷进入,加一句 `(根据你的原文 "<关键词>" 自动锁定)`)

然后打印空行 + `请描述你要做什么?(自然语言或直接贴 SQL 都可以)`,停下等用户。

用户回复后:
- 若自然语言 → 转成 SQL
- 若 SQL → 原样使用
- 在代码块里打印最终 SQL 给用户过目(不要求确认,只是让用户看到),随即进入步骤 3

**用户中途改意 / 改 SQL 的处理**:在步骤 3 还没发起 analyze 之前,如果用户说"等等"/"改一下 SQL"/"换一个写法"/任何示意要修改的话,**立即停止**,不调用 analyze,回到步骤 2 重新收集意图,生成新 SQL,再重新走步骤 3。不允许带着旧 SQL 半途调整后继续执行。

## 步骤 3 — 风险分析 + 确认 + 执行

### 3.1 调用 analyze

```bash
python3 <SKILL_DIR>/db_ops.py analyze --env <ENV> --sql "<SQL>"
```

SQL 里有引号时用 shell heredoc 或转义。解析 stdout 的 JSON。

若 `level == "INVALID"`:打印 `SQL 解析失败:<reasons>`,回到步骤 2(重新收集用户意图)。

若 stdout 包含 `{"error": "config: ..."}`:打印 `配置错误:<error>`,告知用户检查 `<SKILL_DIR>/config.yml`(或运行 `python3 <SKILL_DIR>/db_ops.py self-check` 诊断),结束本次调用。

若 `dry_run_diagnostic` 字段非空:在 banner 风险原因之后**单独一行**展示 `dry-run 诊断: <diagnostic>`(不是风险原因)。

诊断字段可能包含:
- `connect failed: <reason>` — 连库失败(配置错或网络问题)
- `EXPLAIN skipped: <reason>` — SELECT 的 EXPLAIN 报错(SQL 语法问题或权限不足)
- `dry-run failed: <reason>` — UPDATE/DELETE 试跑被 DB 拒
- `large result set (estimated N rows > THRESHOLD)` — SELECT 估算超 `large_select_warn_rows`(默认 100 万),提醒用户加 LIMIT 或 WHERE

### 3.2 打印 banner

EMOJI 映射(必须与 db_ops.py 的 RISK_EMOJI 字典一致):LOW=🟢 MEDIUM=🟡 HIGH=⚠️ CRITICAL=🔴

TEST 模板:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧪 环境: TEST
<EMOJI> 风险等级: <LEVEL>
风险原因: <reasons 逗号拼接>
dry-run 实际影响行数: <estimated_rows | 未知>     (仅供参考,不改变确认流程)
<若 dry_run_diagnostic 非空>
dry-run 诊断: <diagnostic>
</若>
<若 dry_run_sample_rows 非空(仅 SELECT/CTE_SELECT 走 EXPLAIN, DELETE+WHERE 走样本快照,其余分类此字段为空)>
样本(最多 N 行,N 由 config dry_run_sample_rows 决定):
  <每行一条 key=value 拼接>
</若>
SQL:
  <SQL 单行压缩或原样>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

PROD 模板:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔥 环境: PROD (仅生成 SQL,不直连)
<EMOJI> 风险等级: <LEVEL>
风险原因: <reasons 逗号拼接>
SQL:
  <SQL>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**多语句额外提示**:若 `stmt_type == "MULTI"`,在风险原因后单独一行加 `⚠ 包含多条 SQL,请逐条检查`。这是 CRITICAL 的常见误判源,不提醒用户可能盲目输入短语。

### 3.3 按分支处理

#### TEST 分支

| level | 行为 |
|---|---|
| LOW | 直接调用 `exec-test`(不问用户),打印结果 |
| MEDIUM / HIGH | 打印下面的 1/2 提示块,等用户回复 |
| CRITICAL | 打印短语提示,要求精确输入 `yes execute on TEST` |

MEDIUM/HIGH 提示块:
```
是否执行?
  [1] 执行
  [2] 取消
```
用户回 `1` → 调用 `exec-test --sql "<SQL>"`;其他任何回复 → 打印 `已取消。` 结束。

CRITICAL 提示块:
```
🔴 危险操作,请输入确认短语以继续:yes execute on TEST
(输入其他任何内容即取消)
```
用户严格等于 `yes execute on TEST` → 调用:
```bash
python3 <SKILL_DIR>/db_ops.py exec-test-critical --sql "<SQL>" --phrase "yes execute on TEST"
```
其他任何回复(包括大小写不符、多空格、多标点、半角/全角差异)→ 打印 `短语不匹配,已取消(不重试)。` 结束。

**异常分支保护**:若 `exec-test` 返回 `{"error": "CRITICAL level requires exec-test-critical with phrase"}`,说明 Claude 错误地把 CRITICAL SQL 路由到了 `exec-test`(理论上不应发生,因为步骤 3.2 已分类)。打印 `内部流程错误:CRITICAL SQL 被错误路由,请重新激活 db-ops skill。` 结束,不要降级用 exec-test-critical 自动重试。

#### PROD 分支(所有风险等级一律)

```bash
python3 <SKILL_DIR>/db_ops.py render-prod --sql "<SQL>"
```
把 stdout 原样包在 ```sql 代码块里打印给用户,附一句:
> 请复制上方 SQL 到目标执行工具(见 SQL 头部 `目标环境` 行)中执行。

**结束本次调用。** 不要再问"是否继续"。

若用户在 PROD 渲染后继续问任何数据库操作(比如"那再帮我在测试库查一下"/"再来一条 update"),**不要在当前流程接续,也不要在当前响应内自动重启步骤 1**。Claude 必须打印:
> 已结束本次 db-ops 调用。请在新的 prompt 中重新发起请求(skill 会从步骤 0 上下文清零开始)。

然后停下。**重新激活 = 用户必须再发一次新 prompt**,不能在当前响应中"重启流程"。

## 执行结果展示

`exec-test` / `exec-test-critical` 成功时返回 JSON:`{affected_rows, rows, row_count, truncated, elapsed_ms}`

**严格按以下方式展示,不允许把 JSON 原文丢给用户:**

### 有 `rows`(SELECT 类,即 `row_count > 0`)

把 `rows` 渲染成 GitHub-flavored markdown 表格:
- 用 `rows[0]` 的 keys 作为表头列顺序
- 单元格内换行替换为空格、`|` 转义为 `\|`、`null` 显示为空白
- 长字段(>80 字符)截断尾部为 `…`
- 默认最多展示 **50 行**(`display_max_rows` 配置项,见 config.yml options);若 `row_count > 50`,表格末尾追加一行 `_…还有 N 行未展示_`(N = row_count - 50)
- 若 `truncated == true`,表头标题加 `(已截断到 exec_max_rows)` 提示
- 表格上方一行小字标题:`📊 共 <row_count> 行 · 耗时 <elapsed_ms> ms`

示例(用户应看到这种效果):
```
📊 共 3 行 · 耗时 12 ms

| id | name | status |
|---|---|---|
| 1 | 张三 | online |
| 2 | 李四 | offline |
| 3 | 王五 | busy |
```

### 无 `rows` 但 `affected_rows > 0`(INSERT/UPDATE/DELETE/REPLACE)

打印一行:`✅ 已执行。影响行数: <N>,耗时 <ms> ms。`

### 既无 rows 又 affected_rows == 0(DDL / SET / FLUSH 等)

打印一行:`✅ 已执行(无返回结果),耗时 <ms> ms。`

### 出错

打印 `❌ 执行失败:<error>`,然后停下,不要自动重试。

如果用户希望重试(连接超时 / 锁等待 / 临时故障),必须重新激活 skill,从步骤 1 开始 — 不允许在当前流程内私自重试。

### 反模式

- ❌ 直接贴 `{"affected_rows": 1, "rows": [...]}` 这种 JSON 给用户
- ❌ 把 `rows` 用 `- key=value` 的 bullet 列表展示
- ❌ 嫌行多就跳过表头直接说"共 100 行已查询"——必须出表格 + 截断提示
- ❌ SELECT 显示"影响行数: 5"——SELECT 显示 `📊 共 N 行`,不是"影响行数"

执行完后 **停下不自动继续**,等用户下一条指令。

## 反模式(禁止)

- ❌ 用户原文已含"测试服/测试库/test 库"等快捷关键词,Claude 仍打 1.1 banner 或简化"默认 1,等确认?" → 这是 LLM 防御性确认本能,违反 1.0。命中关键词必须直接进步骤 2,不打任何选择/确认 banner
- ❌ 用户一句"查一下测试库 sys_menu"直接进步骤 3 → 必须走步骤 2(确认 SQL)再走步骤 3,不能跳
- ❌ 上下文里"刚才是测试库"→ 本次自动套用 TEST:不行,只有**本次原文**含 TEST 关键词才走 1.0 快捷
- ❌ 用户说"正式服删一下 xxx" → 跳过 1.1 直接进步骤 2:不行,PROD 永远要走 1.1 完整确认
- ❌ dry-run 结果显示影响 0 行 → 判断"无副作用"跳过确认:行数只是信息,不改确认流程
- ❌ CRITICAL 短语差一个字 → 允许"大概匹配":必须字节级完全一致
- ❌ PROD 分支里给出"如果你希望我直连..."的备选:没有备选,PROD 永远只输出文本
- ❌ 用户问"顺便也在正式库做一下" → 本次 skill 直接切换环境:必须结束当前调用,重新走步骤 1
- ❌ 用户在步骤 2 SQL 展示后说"改一下"→ 强行跑完 analyze 再回 step 2:必须立即停下,不发起 analyze
- ❌ exec-test 报 CRITICAL 路由错误 → 自动改用 exec-test-critical 重试:必须打印错误并结束,不允许自动恢复

## 手动验收 checklist(改动本 skill 后跑一遍)

跨平台冒烟:
- [ ] `python3 <SKILL_DIR>/db_ops.py self-check` 返回 `{"ok": true, ...}`(若 config.yml 配置正确)

核心 SKILL 流程:
- [ ] 首次调用打出步骤 1 环境选择块,不默认
- [ ] `SELECT * FROM sys_menu LIMIT 5` → TEST 下 LOW,直接执行返回表格
- [ ] `UPDATE sys_menu SET name='x' WHERE id=1` → TEST 下 MEDIUM,dry-run 行数 + 1/2
- [ ] `DELETE FROM sys_menu WHERE parent_id=-999` → TEST 下 HIGH,样本行展示 + 1/2
- [ ] `DELETE t1 FROM t1 JOIN t2 ON t1.id=t2.id WHERE t2.flag=1` → TEST 下 HIGH(多表删除正则验证)
- [ ] `WITH c AS (SELECT id FROM t) DELETE FROM tg WHERE id IN (SELECT id FROM c)` → TEST 下 HIGH(CTE_DML)
- [ ] `CALL my_proc()` → CRITICAL,要求短语
- [ ] `DROP TRIGGER tr` → CRITICAL(完整 DROP 子类型覆盖)
- [ ] `DELETE FROM sys_menu` (无 WHERE) → TEST 下 CRITICAL,要求输入短语
- [ ] 同上 SQL → PROD 下只输出带注释头的 SQL 文本(头部含 audit-id)

反模式拦截:
- [ ] 前一轮选过 TEST,本轮 SELECT 不含关键词 → 重打步骤 1,不复用环境
- [ ] 用户说"正式库查一下" → 走 1.1 环境选择,不跳过
- [ ] DELETE 返回 0 行 dry-run → 仍打出 HIGH/CRITICAL 确认块,不跳过
- [ ] CRITICAL 短语输入 `yes execute on test`(小写) → 拒绝不重试
- [ ] CRITICAL 短语输入 `yes execute on TEST `(尾部多空格) → 拒绝不重试
- [ ] 步骤 2 SQL 展示后用户说"改一下" → 立即回步骤 2,不调 analyze
- [ ] PROD 渲染后用户问"再查个测试库" → 拒绝接续,提示重新激活

代码层(无 pytest 时用 inline python 跑 `tests/test_classify.py` 中的断言):
- [ ] `python3 -m pytest tests/ -v`(若装了 pytest)全绿
- [ ] audit.log 在 `<SKILL_DIR>/audit.log` 有记录(每次 analyze/exec/render-prod 一行)
