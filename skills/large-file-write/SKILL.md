---
name: large-file-write
description: 写超大文件（预估或已知 >1000 行）时的防 socket 断开策略。用"骨架 + 哨兵 + 分片 Edit"避免单次 Write 触发 `socket connection was closed unexpectedly` / `API Error` / `Write failed`。任何涉及"写大文件"、"生成完整 HTML/Vue/Python 等长文件"、"一次性生成整个 xxxx.xxx"、"文件超过 1000 行"、"分片写"、"chunked write"、"socket closed"、"connection closed unexpectedly"、"write failed"、"写挂了重试" 的诉求（事前预防 / 事后补救），都必须通过本 skill 完成，不要直接 Write 整个长文件。
---

# large-file-write

分片写大文件 skill。核心思路：**单次 Write 的 content 越长，socket 越容易断。把长文件拆成「骨架 + 多次 Edit 追加」**。

## 术语：行数

全文所有"行数"均指**按 `\n` 换行符计数，含空行、含末尾换行、含注释行**。Write 的 `content` / Edit 的 `new_string` 用同一口径。脑内估算时可按"平均每行 40 字符"做粗估（200 行 ≈ 8KB）。

## 绝对规则（不得违反）

1. **预估或声称 >1000 行**的文件，**禁止**单次 Write 整个文件（无条件生效——即使走脚本生成分支失败回落到 Write，此规则仍约束）。
2. **已失败过一次**（收到 `socket closed` / `Write failed` / `API Error`）的文件，**禁止**再用相同长度重试——必须切回分片流程。
3. **单次 Write 或单次 Edit 的 content / new_string 上限 300 行**（按上面"行数"口径计）。
4. **哨兵必须独占一行**，不能嵌在其他内容中间；不能省略哨兵后面的换行。
5. **Final 那次 Edit 必须把哨兵整行连同它的换行一起删掉**，不要留垃圾注释。
6. **Final 之后必须调 Grep 工具验证 `CLAUDE_NEXT` 命中数 = 0**（仅适用骨架分片分支；脚本生成分支产物不含哨兵，以脚本产物的合法性校验代替）——肉眼 / 印象 / "我觉得删干净了" 都不算数。

## 何时启动本 skill

**事前触发**（满足任一即启动，优先靠量化阈值，不依赖用户用特定词）：

1. **Write 前主动行数预估**：任何调 Write 前先估 content 行数，含
   - ≤500 行 → 常规 Write，skill 退出
   - 500~1000 行 → 看内容密度，大段重复 snippet / 内联 SVG / 大字典 / 大样本数据按 >1000 行处理
   - \>1000 行 → 强制走本 skill
2. **已知规模启发式**（基于实测样本；判断依据来自用户 prompt / 需求文档 / plan 文件里的**可观测关键词**，而非脑补）：
   - plan.md 含 ≥10 个 FP 标题（grep `^##.*FP-`）→ 预估 >1500 行（实测 07 plan.md：15 FP → 2423 行）
   - Vue 单页：需求/plan 里列出的组件清单 grep 到 ≥3 个 "dialog"/"弹窗"/"drawer" 关键字 **且** 表单字段 ≥5 个 **且** 带列表 → 预估 >1000 行
   - 自审 / 复盘报告 Round-N：同一文件已追加过 ≥2 轮 → 第 3 轮起累计预估 >1000 行
3. **本会话已有失败记录**：曾收到 `socket closed` / `Write failed` / `API Error` → **无条件**启动，不再预估
4. **用户措辞兜底**：用户明说"一次性写完整的 xxx.html / xxx.vue / xxx.py / xxx.sql"、"生成整个 xxxx"、"输出完整的 xxxx" → 启动（保留作为兜底，优先靠 1~3 的量化触发）

**事后触发**：
- 用户报告 `socket connection was closed unexpectedly` / `API Error: fetch failed` / `Write failed` / "写到一半挂了"
- 此时文件可能**部分写入**，先 Read 确认现状，再决定从哨兵续写还是整体重构

## 流程

### Step 0：选哨兵

行数阈值判定已在"何时启动本 skill"完成，这里只负责**按扩展名选合法注释哨兵**（哨兵必须本身是合法注释，不影响语法）：

| 扩展名 | 哨兵 |
|---|---|
| `.md` / `.html` / `.vue`（template 区）/ `.xml` / `.svg` | `<!-- CLAUDE_NEXT -->` |
| `.js` / `.ts` / `.jsx` / `.tsx` / `.java` / `.go` / `.rs` / `.c` / `.cpp` / `.cs` / `.kt` / `.swift` / `.scala` / `.css` / `.scss` / `.less` | `// CLAUDE_NEXT` |
| `.py` / `.rb` / `.sh` / `.bash` / `.zsh` / `.yml` / `.yaml` / `.toml` / `.conf` / `.ini` / `.dockerfile` / `Makefile` | `# CLAUDE_NEXT` |
| `.sql` | `-- CLAUDE_NEXT` |
| `.vue`（`<script>` 区） | `// CLAUDE_NEXT` |
| `.vue`（`<style>` 区） | `/* CLAUDE_NEXT */` |
| 未知扩展 | 用最保守的 `# CLAUDE_NEXT`（绝大多数 scripting 语言兼容） |

**哨兵固定命名 `CLAUDE_NEXT`**（不用 `NEXT`/`TODO` 这种容易和用户原有代码碰撞的词）。

### Step 0.5 · 文件类型判定（选流程）

不是所有大文件都适合"骨架 + 分片"。按类型走不同分支：

| 文件类型 | 策略 |
|---|---|
| 结构化数据（JSON array fixtures / SQL 批量 INSERT / protobuf text / 大 YAML 配置树） | **走脚本生成分支**（见下文） |
| 流式数据（CSV / log 样本 / NDJSON / 单行单记录的 txt） | 走**无骨架追加分支**（见下文） |
| 代码/文档（HTML / Vue / 各类 .js/.ts/.java/.py 源码 / 长 Markdown / 自审报告） | 走常规**骨架 + 分片**流程（Step 1~Final） |

**脚本生成分支（结构化数据）**：
1. Write 一个 `.py` / `.sh` 脚本（脚本本身通常 <300 行，直接 Write 即可），脚本里用 `json.dump` / `mysqldump` / heredoc 输出到目标文件
2. `Bash(command: "python3 /path/to/gen.py")` 执行
3. 生成后**必须**校验：`Bash(command: "wc -l /path/to/target.json")` 确认行数符合预期；若目标是 JSON array，加 `python3 -c "import json; json.load(open('/path/to/target.json'))"` 做合法性校验
4. 脚本执行失败 / 产物行数异常 → **回到 Step 1 走骨架分片分支**（不要硬重试脚本），此时适用绝对规则 1
5. 脚本产物 ≤500 行 → 直接交付，不再走 skill 其他步骤

**无骨架追加分支（流式数据）**：
- Step 1 写表头（如有）+ 前 ≤300 行 + 末尾哨兵；Step 2~N 纯追加；骨架等于空
- **跳过 Step 1 前置检查**（因为骨架本身为空，不存在骨架超限问题）
- Final / retry 策略照走

选完分支再往下走。下面的 Step 1~Final 默认按**代码/文档**分支描述。

### Step 1：先 Write 骨架 + 首批正文

**Step 1 前置检查 — 骨架规模预估**：先估算骨架行数，粗估公式：

```
骨架行数 ≈ (顶层 section 数 × 5) + 壳/标签/imports 约 20
```

举例：Vue 文件 6 个 section（template 主区 + 5 个弹窗）→ 6 × 5 + 20 ≈ 50 行；若含内联 SVG 200 行 → 骨架就 ≈ 250 行；再加大 JSON schema 声明可能冲到 >300 行。

若骨架预估 >300 行，按下列判断规则二选一：

- **切文件（优先）**：有合适 import/require 路径可抽（项目支持 ES module / require / Python import / Java class）→ 把 SVG / schema / 长常量数组抽到独立文件，主文件骨架回落 <300 行
- **分级骨架**：以下场景**不能切文件**时走这条——（a）单文件 HTML demo / 单文件脚本 / (b) 无合适 import 基础设施 / (c) 用户明确要求单文件交付。做法：先 Write 最小壳（HTML 三段齐 / Vue 三段齐），每段内放一个**带唯一后缀的哨兵**如 `<!-- CLAUDE_NEXT section-header -->` / `<!-- CLAUDE_NEXT section-main -->`（命名建议用语义名 `section-<含义>`，避免 `section-1/2/3` 这种纯序号不容易维护），Edit 时 old_string 包含完整哨兵行即可唯一定位

满足前置检查后继续：

骨架 = 文件的**高层结构占位**：
- HTML/Vue：`<template>` / `<script>` / `<style>` 三段标签齐全，template 里写主 layout 骨架（header/main/footer 等），细节内容留哨兵
- Python：`import` + 所有顶层 `def`/`class` 签名 + 每个函数体内放 `pass  # CLAUDE_NEXT` 或在文件尾放哨兵
- 后端接口/控制器：所有路由声明 + 每个 handler 占位 + 末尾哨兵
- 长文档 Markdown：所有 H1/H2 标题 + 末尾哨兵

首批正文塞 **200~300 行**最核心/最顶层的内容，哨兵放在**最接近未完部分**的位置（通常是文件末尾或某个 section 末尾）。

**Write 调用约束**：
- `content` 总行数 ≤ 300
- `content` 末尾第二行是哨兵（最后一行通常是闭合标签如 `</html>`，或换行）
- 如果只有一个哨兵，建议放在"最容易继续追加"的位置——对 HTML 来说通常是 `</body>` 上一行，对 Python 来说是文件末尾

例（HTML）：
```
<!DOCTYPE html>
<html>
<head>...</head>
<body>
  <header>...</header>
  <main>
    [前 200~250 行主要正文]
    <!-- CLAUDE_NEXT -->
  </main>
</body>
</html>
```

### Step 2~N：每次 Edit 把哨兵替换成「下一批 + 哨兵」

每次 Edit 调用约束：
- `old_string = 哨兵整行`（必须包含哨兵的整行，让 Edit 唯一定位）
- `new_string = 新内容（≤300 行）+ 哨兵`，**哨兵还是原样保留**在新内容末尾
- 单次 Edit 的 `new_string` 总行数 ≤ 300

**如果骨架里有多个哨兵**（比如每个 section 都埋了一个），每次 Edit 只替换一个，用 `replace_all: false`（默认）。若哨兵在多处重复出现，先用上下文把 `old_string` 唯一化（如前面两行 + 哨兵），不能依赖 `replace_all: true`——会踩到还没填的 section。

### Final：把哨兵删掉 + 硬性 Grep 验证

最后一次 Edit：
- `old_string = "\n哨兵整行\n"`（把哨兵行连同前后的换行一并删）
- `new_string = "\n"`（保留一个换行避免文件尾被 join）

或者直接：
- `old_string = 哨兵整行`
- `new_string = ""`（空字符串，Edit 允许）

**硬性验证（不可跳过，绝对规则 6）**：Final Edit 之后**必须**调一次 Grep 工具。

- **单文件场景**（常规）——直接 Grep 目标文件：
  ```
  Grep(pattern: "CLAUDE_NEXT", path: "/Users/foo/project/src/index.html", output_mode: "count")
  ```
  把 path 替换成实际目标文件的绝对路径，不是字面的 `<目标文件绝对路径>`
- **多文件场景**（走了分级骨架切文件分支）——必须对**主文件 + 所有抽出的子文件**逐一 Grep，任一文件命中 >0 都不算交付
- 返回 0 → 交付
- 返回 >0 → 继续 Edit 清剩余哨兵，**再 Grep**，循环到 0 为止

禁止跳过此步直接回复用户"写完了"——肉眼 / 印象 / "我觉得删干净了" 都不算数，必须以 Grep 返回 0 为唯一交付标志。

## 分片过程中失败的 retry 策略

分片本身降低了单次 payload，但 N 次分片的累计成功率仍会衰减（单次 p，N 次 p^N）。任何一次 Edit 挂掉时按以下梯度处理，**禁止盲目原样重试**：

1. **先 Read 文件定位现状**：Edit 在 harness 层原子提交，但 socket 断可能发生在 ACK 丢失 / 服务端已落盘的场景。先 Read 看哨兵还在不在
2. **哨兵仍在原位 → 原样重试 1 次**：payload 不变，网络瞬断可恢复
3. **重试仍挂 → 阈值减半**：下次 `new_string` 收紧到 ≤150 行，分更多次追加
4. **连续 3 次挂 → 降级 50 行/段 或改切文件**：把内容拆到多个小文件 import 回来
5. **哨兵已不在但内容残缺 → 转事后补救流程**：直接跳到下节的"结构合法"或"结构破损"分支（retry 语境下不会出现零字节）。转之前先 `Grep(pattern: "CLAUDE_NEXT", path: 目标文件, output_mode: "count")` 确认哨兵确实 0 命中

核心原则：payload 没有变就不要重试。每次失败都要调整策略（减半 / 拆段 / 切文件），否则只是浪费 tokens。

## 事后补救（已经失败的场景）

用户报错后：

1. **Read 文件**看现状。三种情况：
   - **零字节 / 文件不存在**：直接走 Step 0~N，从头分片
   - **部分写入但结构合法**（有闭合标签、没截断）：在合适位置 Edit 插入哨兵，然后 Step 2~N 续写
   - **部分写入但结构破损**（HTML 半截 tag、Python 半截函数）：**不要硬续写**。把残余部分作为参考，Write 一个全新的骨架覆盖（注意用户可能有手写改动，先征求同意再覆盖）
2. 不要道歉式地再试一次完整 Write。工具层面没变，重试也会挂。

## 额外的 harness 配置建议（独立于本 skill）

分片能解决**大部分** socket 断开问题。但如果用户网络特别差、或单文件真的巨大（>5000 行），建议拉长 Claude Code 的超时：

- Claude Code settings.json 里 `env.CLAUDE_CODE_MAX_OUTPUT_TOKENS` / 相关 fetch timeout
- 具体看 `/config` 或参考 `update-config` skill

这不在本 skill 的自动执行范围，只是同事可选的补救措施。本 skill 的分片策略独立可用。

## 反模式（常见踩坑）

- ❌ 用 `TODO` / `NEXT` / `PLACEHOLDER` 当哨兵 —— 这些词太常见，容易和用户原有内容碰撞，**必须**用 `CLAUDE_NEXT`（绝对规则，非建议）
- ❌ 哨兵不独占一行（比如塞在 `<!-- TODO fill this <!-- CLAUDE_NEXT --> -->` 里）—— Edit 匹配会出乱
- ❌ 单次 Edit 追加 500+ 行"因为我想提速"—— 300 行是 tested 上限，别冒险
- ❌ 不调 Grep 就回复用户"写完了" —— 绝对规则 6，肉眼判断不算交付
- ❌ 对同一个文件用 `replace_all: true` 追加 —— 会同时踩到所有埋好的哨兵，毁掉骨架
- ❌ 不做 Read 定位就**无限**原样重试 —— 分片内第 1 次瞬断允许原样重试 1 次（retry 策略第 2 步），但超过 1 次必须减半 payload 或换策略
- ❌ 脚本生成分支失败后原样重跑脚本 —— 回到 Step 1 骨架分片分支，别硬刚

## 成功标志

- 目标文件（+ 如有子文件）完整写完，语法/结构合法
- Grep `CLAUDE_NEXT` 在主文件 + 所有子文件上命中均为 0
- 若触发过 retry：每次失败都调整了策略（减半 / 拆段 / 切文件），没有盲目原样重试
- 若走脚本生成分支：产物经 `wc -l` + 合法性校验（JSON.load / 可解析）通过
- 过程中每次 tool call 都返回成功，没有收到 socket / fetch 错误
