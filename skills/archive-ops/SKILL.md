---
name: archive-ops
description: 本地归档已完成的需求文档 + 读档查过去相关经验教训。归档：读目录下的 需求.md / *-design.md / *-plan.md → 抽 5 类 tag（模块/技术/症状/方案/文件）+ 摘要 + 教训 → 倒排索引落盘。读档：给一个新需求，自动查出过去相关归档 top-K 并展示教训。用户任何关于"归档这个需求"、"查过去做过类似的没"、"有没有相关经验/教训"、"读档"、"归档"、"/archive"、"/lookup" 的诉求，必须通过本 skill 完成，不要手动读写 ~/.claude/skills/archive-ops/data/ 下的 JSON。
---

# archive-ops

本地归档 + 读档 skill。所有 LLM 抽取在**主 agent 上下文**里做，Python CLI 只做 I/O 与索引维护。

## 绝对规则（不得违反）

1. **不要手动读写 `data/` 下的 JSON。** 索引与归档记录必须通过 CLI 子命令，保证 `by_tag` 与 `by_id` 同步，并使用原子 rename 写入。
2. **tag 维度固定 5 类**：`modules`、`tech`、`problems`、`solutions`、`files`。不能擅自新增（多余维度 CLI 会在 stderr 报 warning 并丢弃）。
3. **抽 tag 时先查 `synonyms.yaml` 做归一**，再尽量复用 `index.json` 里已经出现过的 canonical slug（即 `list` 能看到的那些）。同一个概念在不同归档里应落成同一个 slug，否则索引质量会退化。
4. **破坏性操作（`--force` 覆盖 / `forget` 删除）前必须让用户 `1/2` 确认**：覆盖 → 1 覆盖 / 2 取消；删除 → 1 删除 / 2 取消。
   - 新归档**不需要** 1/2 —— 打印预览让用户扫一眼 tag 抽对了没有，然后直接落盘。抽错了 `forget` 能撤。
   - 只接受 `1` / `2`，其它回复（`好`/`ok`）要求用户重发。用户回 `2` 终止，不换花样重试。
5. **展示 `lookup` 结果必须格式化成 markdown 表格**，不要把 JSON 原文丢给用户。

## 数据位置

- 默认：`~/.claude/skills/archive-ops/data/`（跟 skill 代码捆绑）
- 可覆盖：设 `ARCHIVE_OPS_DATA_DIR` 环境变量（跨项目共享 / 团队 NAS 同步场景）
- **升级 skill 前自己备份 `data/`**，因为 skill 目录可能被覆盖

## 依赖检查（首次使用）

```bash
python3 -c "import yaml" 2>&1
```
import 失败 → 询问用户：
> 缺少依赖 pyyaml，是否运行 `pip3 install -r ~/.claude/skills/archive-ops/requirements.txt`？

同意则执行；不同意则中止。安装成功后本 session 不用再问。

## 核心流程总览

- **归档**：用户说"归档 X"/"/archive X" → 走 §归档三步
- **读档**：用户说"查过去做过 X 没"/"/lookup X"/"有相关经验吗" → 走 §读档三步
- **只读运维**：`list` / `show <id>` 用户直说即可，无需确认
- **删除**：`forget <id>` 走 §forget 流程（跟归档一样要 `1/2` 确认 + `--yes`）

---

## 归档三步

### 步骤 A1 · collect 原文

```bash
python3 ~/.claude/skills/archive-ops/archive_ops.py collect "<需求目录绝对路径>"
```

返回 JSON 样例（`files` 是 `{绝对路径: 文件全文}`）：
```json
{
  "title": "工单消息死锁修复",
  "path": "/path/to/req/20260410-ticket-deadlock",
  "project": "asms",
  "files": {
    "/path/to/req/20260410-ticket-deadlock/需求.md": "# 工单消息死锁修复\n背景:...",
    "/path/to/req/20260410-ticket-deadlock/foo-design.md": "## 方案\n..."
  }
}
```

目录不存在退出码 2 + stderr 有说明,此时**告诉用户"目录不存在,请确认路径"** 并终止,不擅自改路径重试。

### 步骤 A2 · 抽 tag + 摘要 + 教训

在主 agent 上下文里做这件事，**不要叫 CLI 或另一个 skill 去做**。流程：

1. **`Read ~/.claude/skills/archive-ops/synonyms.yaml`** —— 每个 canonical_slug 对应一组同义表达。同义归一在你脑内做，CLI 不做任何 NLP。
2. **调 CLI `list`** 粗扫已有归档；需要更精确则 `show <id>` 看几条已归档的 tag 形态。目的：**复用现有 slug**，避免同概念写成两个新 slug。归档 > 50 条时带 `--project <name>` 先缩小范围。
   - `list` 输出样例：
     ```
     ID                               DATE        PROJECT  TITLE
     ----------------------------------------------------------
     20260410-ticket-deadlock         2026-04-10  asms     工单消息死锁修复
     20260316-ws-async-fail           2026-03-16  asms     WS 异步失败
     ```
   - 从这份表里拿到 **ID 的左侧日期+主题**，它的 tag 形态要 `show <id>` 才看得到。
3. **从 files 里拎信息**抽 5 类（全部归一成英文小写连字符 slug；中文 slug 会破坏跨归档匹配）：
   - `modules`：业务模块（`ticket` / `message` / `websocket` / `permission` / `bi` / `agent-plugin` / `supervision` / `quality-check` ...）
   - `tech`：技术栈（`mysql` / `redis` / `mybatis-plus` / `vue` / `spring-tx` / `websocket-protocol` / `java-concurrent` ...）
   - `problems`：问题症状（`deadlock` / `duplicate-key` / `n-plus-one` / `silent-failure` / `race-condition` / `index-miss` / `long-tx` ...）
   - `solutions`：方案类型（`add-index` / `drop-index` / `after-commit` / `synchronized-session` / `batch-query` / `retry-backoff` / `async-flush` / `tx-shrink` ...）
   - `files`：触及的核心文件（≤5 个，如 `AsmsTicketServiceImpl.java` / `Layout.vue`）
   - **跨维度消歧**：一个词可能跨维度（`websocket` 既是模块业务又对应协议）。规则：
     - 若业务视角使用 → 归 `modules`（如"推送模块"用了 ws）
     - 若协议/库视角使用 → 归 `tech`（如"升级 ws 协议版本"）
     - **实在两者都有** → 两个维度都抽，不重复也不遗漏。tag 在不同维度里是独立索引的，多抽无代价。
4. **写 summary**：2-3 句话，描述"场景 → 根因 → 方案"。
5. **写 lessons**：1-3 条**可复用教训**。判断标准：把项目名/文件名去掉后，这句话在别的项目里读仍然有意义。
   - ✅ "事务内禁止做 IO 和异步调度，用 afterCommit 回调"
   - ✅ "复合索引 (A,B,time) 不能替代单列 (time)，删索引前 grep 所有纯时间范围查询"
   - ❌ "本次修改了 AsmsTicketServiceImpl.java 的 sendMessage 方法"（事实陈述，不是教训）
   - ❌ "修 bug 后发布上线"（不可复用）
6. **构造 id**：`<YYYYMMDD>-<kebab-case-topic>`，如 `20260416-sendmsg-tx-deadlock`。正则 `^[A-Za-z0-9][A-Za-z0-9_\-]{0,99}$`（字母数字/下划线/连字符，首字符字母数字，长度 ≤ 100）。非法字符如 `/` `.` `\n` 会被 CLI 拒绝（路径穿越防护）。

### 步骤 A3 · 预览 + 落盘

打印预览后**直接调 `archive-store` 落盘**，不问 1/2。抽错了用户自己会说"tag 不对，重来" / "别存了 forget 掉"，而且 `forget` 能撤销，不需要再加一道确认墙。

预览模板：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 归档: <title>
路径: <path>
项目: <project>
ID: <id>

Tags:
  modules:   <逗号拼接>
  tech:      <逗号拼接>
  problems:  <逗号拼接>
  solutions: <逗号拼接>
  files:     <逗号拼接>

摘要: <summary>

教训:
  1. <lesson 1>
  2. <lesson 2>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

然后立刻调 `archive-store`：
```bash
python3 ~/.claude/skills/archive-ops/archive_ops.py archive-store \
  --id "<id>" \
  --title "<title>" \
  --path "<path>" \
  --project "<project>" \
  --tags-json '<json>' \
  --summary "<summary>" \
  --lessons-json '<json>'
```

返回 `{ok: true, id, replaced}`：
- `replaced=false` → 新归档，打印 `✅ 已归档: <id>`
- `replaced=true` → 覆盖完成，打印 `✅ 已覆盖: <id>`（只有走过 §覆盖流程才会到这里）

#### 覆盖流程（id 冲突）

CLI 返回 `{ok: false, error: "id 已存在..."}` + 退出码 3 时，**不能自作主张加 --force**。标准流程：

1. 给用户看冲突提示：
   ```
   ⚠️ id <id> 已存在（之前归档过同名需求）
   [1] 覆盖旧归档
   [2] 取消（建议改 id 比如加后缀 -v2）
   ```
2. 用户回 `1`：
   - 若用户只是"再跑一次" / 修复了其它字段 → 重跑**完全一样**的命令 + `--force`
   - 若用户说"改下 tag / summary 再保存" → **先回到 A2 重抽**，重新打 A3 预览，然后带着新内容跑命令 + `--force`（覆盖前不再问一次 1/2，用户在第 1 步已经同意了覆盖）
3. 用户回 `2` → 终止；可以问"要不要改 id 再来一次"，但不能自己改了重试

---

## 读档三步

### 步骤 L1 · 拿到当前需求文本

两条路径**互斥**（不可两个都走），判断优先级：**只要用户消息里包含看起来像目录的字符串**（以 `/` 开头、含 `~` / `./` 开头、或用反引号包住的疑似路径）→ 走路径 A；否则走路径 B。

- **路径 A（用户给了目录）**（如"帮我查 `/path/to/req/` 有没有相关经验"）→ `archive_ops.py collect <dir>`，把返回的 files JSON 当输入
- **路径 B（用户只给自然语言）**（如"查过去做过死锁相关需求没"）→ 直接把用户的原话当 tag 抽取的输入文本，**不去主动要求用户补目录**

边界：用户既给目录又带描述（"查 `/path/to/req/` 有没有死锁相关"）→ 走路径 A，描述只作为 tag 抽取时的辅助 hint，不再让用户选。

### 步骤 L2 · 抽查询 tag

跟归档步骤 A2 同样的流程抽 5 类 tag，**但不需要 summary/lessons**（只用于查询）。稀疏也没关系：缺少某维度就留空数组。

### 步骤 L3 · 查询 + 呈现

```bash
python3 ~/.claude/skills/archive-ops/archive_ops.py lookup \
  --tags-json '<json>' \
  --top 5
```

CLI 返回 JSON 数组，每条含 `{id, title, path, project, date_archived, score, matched_tags, summary, lessons, tags}`。

**严格按下面格式呈现**（不要贴 JSON 原文）：

```
🔍 查到 <N> 条相关归档（按匹配分降序）

| 分 | ID | 项目 | 标题 | 命中 Tag | 教训精要 |
|---|---|---|---|---|---|
| <score> | <id> | <project> | <title> | <matched_tags 逗号拼接> | <lessons[0] 截断 40 字符> |
...

详情请说"展开 <id>"或"读 <id>"，我会 Read 对应 path。
```

- "截断 40 字符"：你自己数字符截断（中英文都算 1 个字符），末尾加 `…` 提示还有后续；不必严格精确，±2 字符可接受
- 列"项目"帮用户快速跳过不相关项目的命中

若 `lookup` 返回 `[]` →
```
🫥 没查到相关归档。
可能原因：
  - tag 太窄（只抽到 1 个 slug）→ 要不要换个维度再试一次？
  - 索引是空的（新用户/新机器）→ 先归档几条经验再回来查
```

### 若用户想展开某条

用结果里的 `path` 字段直接 `Read <path>/需求.md`。必要时再 `Read` 同目录的 design/plan。path 是当时归档时的绝对路径，换机器可能失效——这时候 fallback 是 `show <id>` 看 summary/lessons 就够了。

---

## forget 流程（删除不可逆）

`forget` 是**不可逆**删除，护栏跟归档同级：

1. 用户说"删掉 <id>" / "/forget <id>"
2. 先 `show <id>` 看这条归档存在不存在。show 返回 `{ok: false, ...}` + 退出码 3 → 告诉用户 "id 不存在" 并终止，不要擅自改拼写重试
3. 打印确认框（**格式化 show 输出的关键字段**，不要贴 JSON 原文给用户）：
   ```
   🗑️  要删除归档: <id>
   标题: <title>
   [1] 删除
   [2] 取消
   ```
4. 用户回 `1` → `archive_ops.py forget <id> --yes`
5. CLI 不带 `--yes` 会直接返回 `ok: false` + 退出码 4（代码层护栏）

不要把 forget 当"清理老归档"用——归档就是留给未来查的，只在**错归档**场景才删。

---

## 被其他 skill / CLAUDE.md 调用

调用方自己负责 LLM 抽 tag，直接调 `lookup --tags-json '...'`，消费 JSON 结果。
调用方**有责任**把结果表格化呈现给用户（不要贴 JSON 原文）。本 skill 自身对调用方无感。

---

## 维护命令

```bash
# 索引一致性检查（崩溃/手动误改 data/ 后跑）
python3 archive_ops.py fsck
# 发现不一致时自动修
python3 archive_ops.py fsck --repair
```

fsck 检查三类问题：
- `orphan_files`：`archives/` 里有文件但 `by_id` 漏
- `stale_index_entries`：`by_id` 有项但 `archives/` 缺文件
- `dangling_tag_refs`：`by_tag` 引用的 id 已不存在

全 OK 退出码 0；发现不一致但没加 `--repair` 退出码 5。

---

## 反模式（禁止）

- ❌ 手动 `cat data/index.json` / `Write data/archives/xxx.json`：绕过原子写，`by_tag` 和 `by_id` 会错位
- ❌ 把 `lookup` 返回的 JSON 原文贴给用户：难读；必须表格化
- ❌ 抽 tag 时塞第 6 维（如 `risk`、`urgency`）：CLI 会 stderr warn 并丢弃该维度,但 stderr 信息用户看不到,你会以为成功了其实索引不全——**如果 CLI stderr 有 warning 务必把原文贴给用户**
- ❌ 覆盖/删除前不走 `1/2` 就直接调 CLI：**破坏性操作**护栏；新归档不属于此类
- ❌ 新归档加 1/2 问用户："保存吗?":这是多余的确认墙,归档可撤销,预览完直接调 `archive-store` 即可
- ❌ 用户没明确回 `1` 时自作主张加 `--force`：覆盖是用户决策，不是你的
- ❌ 抽 tag 时用中文做 slug（比如 `modules: [工单]`）：跨归档不归一就没法匹配
- ❌ lessons 写成"本次改了 XXX"这种事实陈述：去掉项目/文件名后还读得懂才是教训
- ❌ 用 `forget` 做"清理老归档"：归档本来就该留着；只在错归档时删
- ❌ 用户给了目录但你又来问"要自然语言描述吗"（或反过来）：L1 的两条路径是互斥的，别来回绕

## 手动验收 checklist（改动本 skill 后跑一遍）

- [ ] `collect` 非空目录 → 返回 `{title, path, project, files}`
- [ ] `collect` 不存在目录 → 退出码 2 + stderr
- [ ] `archive-store` 新 id → `ok: true, replaced: false`；同 id 不加 `--force` → 退出码 3
- [ ] `archive-store --force` → `ok: true, replaced: true`
- [ ] `archive-store --id "../evil"` → 退出码 1 + 格式错误（路径穿越防护）
- [ ] `archive-store --id "foo.v2"` → ok（点号兼容历史 id）；`--id "foo..v2"` → 退出码 1（`..` 显式拒绝）
- [ ] `ARCHIVE_OPS_DATA_DIR=/nonexist/path` → stderr warn 后新建目录,不静默飘走
- [ ] `archive-store --tags-json '{"risk":["high"]}'` → stderr 有 warning "risk 已丢弃"
- [ ] `lookup` 单 tag 命中 → 返回 ≥ 1 条
- [ ] `lookup` 多 tag → 按加权分降序（problems=solutions=3 > modules=2 > tech=files=1）
- [ ] `lookup --top -1` → 退出码 1
- [ ] `lookup --tags-json '{"modules":"mysql"}'`（值非 list）→ stderr 有 warning 并忽略该维度
- [ ] `lookup` 完全不命中 → `[]` 退出码 0
- [ ] `list` → 表格输出，带 date/project/title
- [ ] `forget <id>` 不带 `--yes` → 退出码 4；带 `--yes` → ok 且 `lookup` 同 tag 不再命中
- [ ] `fsck` 干净索引 → ok: true；手动删 `archives/xxx.json` 后 `fsck` → ok: false + stale_index_entries 非空
- [ ] `synonyms.yaml` 改坏 YAML 语法 → skill 仍能跑（同义归一是主 agent 脑内做的，CLI 不依赖）
