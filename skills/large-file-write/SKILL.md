---
name: large-file-write
description: 写超大文件（预估或已知 >1000 行）时的防 socket 断开策略。用"骨架 + 哨兵 + 分片 Edit"避免单次 Write 触发 `socket connection was closed unexpectedly` / `API Error` / `Write failed`。任何涉及"写大文件"、"生成完整 HTML/Vue/Python 等长文件"、"一次性生成整个 xxxx.xxx"、"文件超过 1000 行"、"分片写"、"chunked write"、"socket closed"、"connection closed unexpectedly"、"write failed"、"写挂了重试" 的诉求（事前预防 / 事后补救），都必须通过本 skill 完成，不要直接 Write 整个长文件。
---

# large-file-write

分片写大文件 skill。核心思路：**单次 Write 的 content 越长，socket 越容易断。把长文件拆成「骨架 + 多次 Edit 追加」**。

## 绝对规则（不得违反）

1. **预估或声称 >1000 行**的文件，**禁止**单次 Write 整个文件。
2. **已失败过一次**（收到 `socket closed` / `Write failed` / `API Error`）的文件，**禁止**再用相同长度重试——必须切回分片流程。
3. **单次 Write 或单次 Edit 的 content / new_string 上限 300 行**（不含空白行/注释也一样，按总行数算）。
4. **哨兵必须独占一行**，不能嵌在其他内容中间；不能省略哨兵后面的换行。
5. **Final 那次 Edit 必须把哨兵整行连同它的换行一起删掉**，不要留垃圾注释。

## 何时启动本 skill

**事前**触发：
- 用户明说"一次性写个完整的 xxx.html / xxx.vue / xxx.py / xxx.sql"、"生成整个项目文件"、"输出完整的 xxxx"
- Claude 自己判断 content 会 >1000 行（典型：单文件大前端、long-form 文档、大量样例数据、完整后台页面）
- 已有失败记录（本会话收到过 socket 断开错误）

**事后**触发：
- 用户报告 `socket connection was closed unexpectedly` / `API Error: fetch failed` / `Write failed` / "写到一半挂了"
- 此时文件可能**部分写入**，先 Read 确认现状，再决定从哨兵续写还是整体重构

## 流程

### Step 0：预估规模 + 选哨兵

估算目标文件最终行数。若 **≤500 行**，skill 退出（走常规 Write）。**500~1000 行**取决于内容密度，若有大段重复 snippet（如 SVG、长 CSS、大字典），按 >1000 行处理。

按目标文件扩展名选哨兵字符串，必须保证哨兵**本身是合法注释**（不影响语法）：

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

### Step 1：先 Write 骨架 + 首批正文

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

### Final：把哨兵删掉

最后一次 Edit：
- `old_string = "\n哨兵整行\n"`（把哨兵行连同前后的换行一并删）
- `new_string = "\n"`（保留一个换行避免文件尾被 join）

或者直接：
- `old_string = 哨兵整行`
- `new_string = ""`（空字符串，Edit 允许）

Final 之后 **Read 一次确认**文件里不再有 `CLAUDE_NEXT`。如果还有，继续 Edit 直到清零。

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

- ❌ 用 `TODO` / `NEXT` / `PLACEHOLDER` 当哨兵 —— 这些词太常见，容易和用户原有内容碰撞，建议用 `CLAUDE_NEXT`
- ❌ 哨兵不独占一行（比如塞在 `<!-- TODO fill this <!-- CLAUDE_NEXT --> -->` 里）—— Edit 匹配会出乱
- ❌ 单次 Edit 追加 500+ 行"因为我想提速"—— 300 行是 tested 上限，别冒险
- ❌ 忘了 Final 那步，留一堆 `CLAUDE_NEXT` 注释在文件里 —— 交付前 Grep 一次
- ❌ 对同一个文件用 `replace_all: true` 追加 —— 会同时踩到所有埋好的哨兵，毁掉骨架
- ❌ 事后用原样长度重试 —— 浪费 time + tokens，socket 还是会断

## 成功标志

- 目标文件完整写完，语法/结构合法
- Grep `CLAUDE_NEXT` 命中零次
- 过程中每次 tool call 都返回成功，没有收到 socket / fetch 错误
