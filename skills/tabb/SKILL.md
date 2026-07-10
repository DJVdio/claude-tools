---
name: tabb
description: 去中心化黑板（blackboard）多 agent 编排规则。仅通过 /tabb 手动触发，不自动触发。用于"多个 agent 并行改同一仓、彼此需要自助避让文件冲突与交接信息、不想让主 agent 成为协调瓶颈"的协作形态——agent 通过共享黑板文件轮询协调，而非事事过主 agent 中转。是 ta 主从星型编排的去中心化替代形态。
---

# Agent Team 黑板编排（tabb）

## Overview

把一次会话变成一支**自组织**开发团队：**协调不过主 agent，而是通过文件系统上的共享黑板完成**。主 agent 从"消息路由中枢"降级为**黑板管理员 + spawner + 用户接口 + 收口驱动**；agent 之间靠轮询黑板自助认领任务、自助避让文件冲突、自助交接产出。核心收益：主 agent 不再是每一次跨 agent 协调的必经瓶颈，协调延迟与主上下文负担都下放到黑板。

**tabb 最不可替代的价值是「多 agent 并行改同一仓时的文件争用协调」**——用**原子 lockfile**（`mkdir` 建锁目录）让并行 agent 自助独占文件、避让互盖，全程零主 agent 介入、零打扰用户。任务认领 / 决策上抛 / 交接这几块是配套（一个够强的模型不装 tabb 也能做个七八成），**唯独"去中心化文件避让"是它区别于 ta 主从编排的硬内核**。选 tabb 的第一判据永远是：**文件冲突协调是否频繁到值得下放**。

**这是 [[ta]] 主从星型编排的去中心化替代形态。** 选型口径见文末。

## 一条诚实的边界（务必内化，别误用）

这个 harness 的 agent 间通信原语只有四条：主 agent `spawn` 子 agent、主 agent `SendMessage` 给在途子 agent、子 agent `return` 给主 agent、**所有 agent 共享同一文件系统**。**没有"子 agent → 子 agent"这条边**——子 agent 不知道兄弟名字、无寻址权限、被 dispatch 时还被要求忽略编排 skill。

所以 tabb 的"去中心化"**只发生在协调层，不在派单层**：

- **协调层去中心化** ✅：谁锁哪个文件、谁认领哪个任务、谁交接给谁——这些走黑板，agent 之间自助解决，不过主 agent。
- **派单层仍是中心化** ⚠️：主 agent 仍是唯一 spawner。别幻想纯 mesh / agent 互相 spawn——原语不支持，硬试只会失败。

**铁律：主 agent 不自己执行任务。** 读代码、改代码、跑测试、跑 git 都派给 subagent；主 agent 只做编排决策、黑板维护、向用户交互，以及为核实实况做的轻量只读探查。任务再小、用户再说"你直接改"，也是派一个 subagent 或先回问口径，绝不自己上手。

**铁律的唯一例外——建/维护黑板本身：** 主 agent **可以直接**创建与维护 `.tabb/board.md`、`.tabb/journal.md`（建目录、写表头、当清道夫修脏行）。这是**编排设施**，不是"业务任务"，不违反铁律，也不必为它派 bootstrap agent（多此一举）。判据一句话：**只要动的是 `.tabb/` 里的协调文件，主 agent 自己来；只要动的是目标仓库的业务代码 / `.gitignore` / 任何会进 git 的文件，一律派单。**（`.tabb/` 加进目标仓 `.gitignore` 这一步属于后者——改的是仓库文件——交给 git-ops 顺手做。）

**铁律二：跳数匹配复杂度（不是规模），别无脑 scout→impl 两跳。** 黑板机制（尤其 `[HANDOFF]` 交接）容易让人误以为"标准姿势=先派 scout 摸链路、写 HANDOFF、再派 impl 接"——**不是**。展开两跳的判据是**复杂度**（链路不明 / 根因需要先摸清），**不是任务大小**：

- **不复杂的任务（无论大小）→ 派一个 general-purpose agent 一站式**：它自己 pull 任务 → 走认领协议锁文件 → 就地查+改+验 → 写 `[DONE]`，**全程不拆 scout、不写 `[HANDOFF]`**。两跳既慢，又平添一次交接。
- **任务大但不复杂 → 拆成多个可并行的一站式小任务**（各自认领、各自锁文件），**不是**摊成 scout→impl；大 ≠ 该先 scout。
- **任务复杂（链路/根因摸不清、且摸清结论要喂给多个并行下游）→ 才展开 scout→impl 两跳**，用 `[HANDOFF]` 交接（这才是招牌案例的适用场景）。
- **伸缩下限是"一个 subagent"**，不是"凡事先 scout"。拿不准就默认一站式；只有当"得先摸清才能动手、且侦察产物要被多个下游复用"时，才值得独立 scout。

一句话：`[HANDOFF]`/scout 是**复杂任务**的工具，不是每单默认动作、更不是"大任务"的同义词。队列里一个能一站式吃掉的任务（哪怕不小），就派一个 general-purpose agent 吃掉，别拆。

## 黑板物理布局（冷热拆分是胜负手）

```
.tabb/
  locks/        ← 文件锁，每把锁一个原子目录（mkdir 建 / rm 放），零共享热文件
  board.md      ← 任务队列，刻意保持极小，只放认领指针
  journal.md    ← 冷日志，append-only，按需读，可轮转
```

**为什么这么分**：把三种东西按"是否需要互斥 / 是否需要全局视图"分开，各用最合适的原语：

- **文件锁需要真互斥** → 用文件系统的**原子原语**（`mkdir` / `O_CREAT|O_EXCL`）。每把锁一个独立目录 `.tabb/locks/<编码后的文件路径>`，**没有共享热文件、没有读改写竞态**——同一时刻只有一个 agent 能 `mkdir` 成功，天然互斥。这比"往一张共享锁表里追加行再回读比时间戳"又快（少一半工具往返）又对（真原子，无 TOCTOU 窗口）。
- **任务队列需要全局视图**（谁在做什么、还有什么没人领） → 留在 board.md 一张小表，读一眼看全部。它仍是读改写、非原子，但认领撞车远比文件锁少，靠回读兜一下够用。
- **完工/交接/决策是 append-only 广播** → 进 journal.md，每个 agent 只追加自己的行，天然不争。

### `.tabb/locks/`（文件锁，原子）

每把锁一个目录，目录内一个 `meta` 记录持有者+时间戳（供主 agent 看"谁锁了啥"、清道夫判死锁）：

```
.tabb/locks/src__auth.ts/meta   →  "impl-auth src/auth.ts 1720579200123456789"
```

抢锁 = `mkdir` 那个目录（成功即独占）；放锁 = `rm -rf` 它。协议见下节。

### board.md（任务队列，恒小）

```markdown
## 任务队列
| 任务 | 认领者 | 状态 |
|---|---|---|
| 修登录鉴权 | impl-auth | doing |
| 加店铺列表 | — | open |
```

只放认领的**指针**，任何正文（根因、改动、交接细节）都不进 board.md，进 journal.md。

### journal.md（冷、不抢）—— append-only

每个 agent 只 append 自己的行，天然不争用；主 agent 和下游 agent 按需读。三类条目，用 tag 前缀区分：

```markdown
[DONE] impl-auth | 修登录鉴权 | 根因 src/auth.ts:42 空指针 | 改 auth.ts+login.ts | 测试红→绿 | 无遗留
[HANDOFF] scout-signup → impl-signup | 链路摸清：注册走 api/signup.ts，校验在 validators.ts:88   ← 这是复杂任务的 scout→impl 形态；不复杂就别照抄，直接一站式（见铁律二）
[DECISION] impl-billing | 是否清理 2023 年前的废弃订单数据？涉及生产写，待用户拍板
```

## 文件锁协议（`.tabb/locks/` 上的原子锁）

用 `mkdir` 的原子性做互斥——**没有回读、没有比时间戳、没有竞态窗口**。**改任何文件 F 前后，各一条 Bash：**

**抢锁（一条 Bash，原子）：**
```bash
L=.tabb/locks/$(printf '%s' "F" | sed 's#/#__#g')
TS=$(python3 -c 'import time;print(time.time_ns())')   # 可移植时间戳；macOS 的 BSD date 不支持 %N
mkdir "$L" 2>/dev/null && { printf '%s %s %s\n' "<你的id>" "F" "$TS" > "$L/meta"; echo GOT; } || echo BUSY
```
- `GOT` → 你独占了 F，开改。
- `BUSY` → 别人正持锁（`mkdir` 因目录已存在而失败）→ **退避**：回队列拉别的 open 任务，稍后重试 F。绝不为等一把锁空转。
- 注：meta 里的时间戳只是给主 agent 看/参考，**锁的正确性只靠 `mkdir` 原子性、死锁判定用锁目录 mtime，都不依赖它**——所以 `date +%s%N`（GNU）能用就用、macOS 上换成上面的 `python3 time.time_ns()` 即可，别用会吐出字面 `N` 的 BSD `date +%s%N`。

**放锁（改完立即，一条 Bash）：**
```bash
rm -rf "$L"     # 然后向 journal.md append 一条 [DONE]
```

为什么原子：`mkdir` 是 OS 级原子操作，同一路径同一时刻**只有一个创建者成功**，其余全部失败。所以"检查有没有被锁"和"抢锁"合成了一次不可分割的动作——不需要先读一张表、再写、再回读校验谁最早。省一半工具往返，还根除了旧乐观锁的 TOCTOU 竞态。

关键点：**锁的是文件，不是任务**。同一任务可能顺次锁多个文件；锁只在真正 Edit 某文件的窗口内持有，干完立刻 `rm`，别攥着不放拖死别人。

## 四区块怎么协同

| 区块 | 在哪 | 谁写 | 谁读 | 作用 |
|---|---|---|---|---|
| 文件锁 | `.tabb/locks/*`（原子目录） | 干活 agent（`mkdir` 抢 / `rm` 放） | 抢锁 agent + 主 agent（`ls` 看占用） | 并行 agent 原子独占文件、自助避让互盖 |
| 任务队列 | board.md | 主 agent 播种；空闲 agent 认领 | 所有 agent | pull 模型：空闲 agent 自助拉活，不靠主 agent 逐个 push |
| 完工/交接 | journal.md | 完工 agent | 下游依赖 agent + 主 agent | agent→agent 间接交接：下游轮询到 `[HANDOFF]` / `[DONE]` 就接着干 |
| 待用户拍板 | journal.md | 撞到设计/数据/生产决策的 agent | 主 agent 轮询→上抛 | agent 不自裁，写 `[DECISION]` 挂起，等主 agent 上抛用户回话 |

## 主 agent 职责（残余，但关键）

1. **init 黑板**：会话组队即**自己建**（属铁律例外）`.tabb/locks/`（空目录）、`.tabb/board.md`（一张任务队列空表 + 表头）、`.tabb/journal.md`；`.tabb/` 加进目标仓 `.gitignore` 这步改的是仓库文件，派 git-ops 顺手做。
2. **播种任务队列**：把用户需求拆成 open 任务写进 board.md 任务队列。大需求先拆成多个可并行小任务（拆分方案一句话报备用户，不阻塞）。**有依赖的下游任务先以 `blocked:等[HANDOFF]xxx` 播种、认领者留空**，别让下游 agent 一 spawn 就空转抢没就绪的活；上游交接信号出现后再由主 agent 把它从 `blocked` 提为 `open`（见职责 4）。
3. **spawn worker**：每张派单内嵌"tabb 协议块"（见下）。仍是唯一 spawner。
4. **轮询上抛 + 门禁放行**：定期读 journal.md，(a) 见 `[DECISION]` → 用带推荐的选项上抛用户，用户回话后把裁决写回 journal，相关 agent 轮询到即恢复；(b) 见 `[HANDOFF] 上游 → 下游` → 把它当"下游可以开工了"的**门禁信号**：把 board 里对应下游任务从 `blocked` 提为 `open` 并 spawn 下游 worker。**关键——主 agent 只做门禁放行，不把 `[HANDOFF]` 的正文复述进下游派单**；下游派单只点一句"你的输入是 journal 里那条 `[HANDOFF]`，自己去读"，让下游直接读黑板。这样交接**内容**始终不过主 agent（不污染主上下文），只有 spawn **门禁**过主 agent——正是"协调层去中心化、派单层中心化"的落地形态。
5. **进度汇报**：从 board（谁持什么锁、任务认领状态）+ journal（`[DONE]` 行）渲染进度，复用 [[ta]] 的分段里程碑进度条（**无平滑百分比**——subagent 没连续完成度信号，硬凑即编造）。
6. **驱动收口**：`[DONE]` 累积到批次阈值或用户说"收口"时，派 git-ops 从 journal 读改动清单做白名单提交。
7. **黑板清道夫**：见异常处理——回收死锁、清理写花的行。

**主 agent 不再路由 agent 间协调**：谁等谁、谁避让谁，是黑板的活。主 agent 只在"上抛用户"和"回收异常"时介入。

## 派单 prompt 的「tabb 协议块」

每个 worker 派单必须内嵌以下整块（这是 tabb 区别于 ta 派单的核心增量），缺了 agent 就不会参与黑板协调：

```
【tabb 黑板协议 —— 动手前通读】
黑板路径：<仓库绝对路径>/.tabb/board.md（热索引）、/.tabb/journal.md（冷日志）
你的 agent-id：<角色-语义，如 impl-auth>

文件避让（改某文件 F 前后各一条 Bash，用原子锁，不是改共享表）：
  抢锁：L=.tabb/locks/$(printf '%s' "F" | sed 's#/#__#g')
        TS=$(python3 -c 'import time;print(time.time_ns())')   # 可移植；macOS 的 BSD date 不支持 %N
        mkdir "$L" 2>/dev/null && { printf '%s %s %s\n' "<你的id>" "F" "$TS" > "$L/meta"; echo GOT; } || echo BUSY
  GOT → 你独占 F，开改；BUSY → 别人正持锁，退避：回队列拉别的 open 任务，稍后重试 F（别为等锁空转）
  改完立即放锁：rm -rf "$L"
  原理：mkdir 是原子操作，同一时刻只一个 agent 建得成，天然互斥——不用读表、不用回读、不用比时间戳。meta 时间戳只是参考，锁正确性不依赖它。

拉活（pull）：干完手头任务，去 board.md 任务队列认领下一个 open 任务（把认领者改成你、状态改 doing）。
交接：产出对下游有用的结论时，向 journal.md append [HANDOFF] <你> → <下游> | <要点带 file:line>。
决策上抛：撞到设计语义/数据写/生产写决策，别自裁——向 journal.md append [DECISION] <你> | <问题>，停下等主 agent 回话。
里程碑（必带，否则主 agent 没法给用户渲染进度条）：按你这单的实际内容切有序里程碑（小任务 3-5 个，如 `读配置→改鉴权→跑测试→修边界`），**每跨过一个就在输出里打一行醒目标记** `【里程碑 N/总 ✓ 语义】`。这是主 agent 渲染分段进度条的唯一可靠信号，缺了进度就只能瞎猜。
回报格式（完工必做——写 journal 不算回报）：干完这单，**必须以一条 return 消息回报给主 agent**——根因 file:line、改动清单、测试证据(红→绿)、遗留点、里程碑全过 N/N。**你往 journal 写的 [DONE]/[HANDOFF] 只是给黑板留痕，不等于回报；绝对别写完 journal 就 idle 停住不 return——主 agent 等的就是你这次 return，你一 idle 它只能来催，白费一轮。** 没有下一个 open 任务可拉、也没在等锁，就带着回报 return 结束。
```

派单时把上面模板里的「里程碑」那行按本单实际内容填成具体清单（别原样留占位）。其余派单要素沿用 [[ta]] 的 impl 类标准：口径原话、已知侦察结论、先红后绿、验证命令与基线白名单。

## 派单落地：只发工具调用，不复述正文

同 [[ta]] 的硬约束，一字不改：

- **SendMessage 只带 `to` / `summary` / `message` 三个参数**，多带字段会 malformed，malformed 是主上下文污染失准的起点。
- **message 全文只进工具调用，不抄进给用户的可见输出**。给用户每张派单只登记一行——`→ 已派 impl-auth：修登录鉴权（黑板协调）`。
- **正文永远不贴派单原文 / 完整 prompt / 子 agent 产出**；用户要看细节点开底部 agent 面板或看 TaskOutput。

自查红线（出现任一条即停，回到干净三参数工具调用）：正文冒出 `<invoke>` / `<parameter>` 字样；SendMessage 带了三参数以外的字段；你在正文"描述/排版"一次派单而不是直接作为工具调用发出。

## 定期回报循环

用户要求持续回报时，用 ScheduleWakeup 建自驱循环（间隔约 270 秒，prompt 自带续排逻辑）。tabb 的每次醒来比 ta 多一步"读黑板"：

- **`ls .tabb/locks/`** 掌握文件锁占用、**读 board.md** 掌握任务队列 → **读 journal.md 新增行**（`[DONE]` 定位完工、`[DECISION]` 定位待上抛、`[HANDOFF]` 掌握交接）→ 轮询各在途 agent 的 `TaskOutput` 扫里程碑标记 → 给超一个周期没消息的 agent 补催。
- **完工却 idle 不回报**（尤其只读 scout：把结论写进 journal 就以为交差、停住不 return）→ 立刻 `SendMessage` 向它要一份 return 式回报（点名要根因/改动/遗留）。这是 tabb 高发坑，派单协议块已要求"写 journal ≠ 回报、完工必 return"，但仍要在循环里兜：`TaskOutput` 显示活已干完、journal 也有它的 `[DONE]`/`[HANDOFF]`，人却 idle → 就是这个症状，直接催。
- 有 `[DECISION]` 未上抛 → **立刻上抛用户**，别攒着。
- 给用户输出**进度表带分段进度条**（任务 / agent / 进度条 / 当前阶段），进度条列必填，渲染与 fallback 同 [[ta]]（点亮到 agent 最新里程碑标记那段，拿不到标记填 `？/？ 无里程碑信号` 并回补）。
- 用户随时问"进度如何" → 即时刷一次。
- 仍有 agent 在工作 → 再排下一次；**全员空闲且任务队列无 open → 输出最终状态，停止循环**。

## 异常处理手册

| 症状 | 处置 |
|---|---|
| 抢锁失败（`mkdir` 返回 BUSY） | 协议内既定：退避，回队列拉别的 open 任务，稍后重试该文件；别为等锁空转 |
| 死锁（agent 挂了/失联还占着锁目录） | 主 agent 当**黑板清道夫**：`.tabb/locks/*/meta` 里持有者已 idle/失联、且锁目录 mtime 超时 → `rm -rf` 该锁目录、把任务退回 open，spawn 新 agent 接替（派单交代工作区现状） |
| 完工却 idle 不回报（**tabb 高发**：scout 写完 journal 就停住不 return） | 立刻 `SendMessage` 要 return 式回报（点名要根因/改动/遗留）；派单协议块已钉"写 journal ≠ 回报、完工必 return"，循环里再兜一道 |
| agent 连续 2-3 次 idle 且不响应 | 不再纠缠，spawn 新 agent 接替，派单交代工作区 + 黑板现状；旧 agent 弃用不删；`rm -rf` 它占的锁目录 |
| 两 agent 抢同一 open 任务都改成 doing | 任务队列仍是读改写、非原子：后读者回读发现认领者不是自己 → 让位，回队列拉别的；主 agent 巡检去重 |
| board.md 膨胀 | 设计上恒小（只放认领指针）；若仍变大是有人往里塞正文——纠正为写 journal。journal 过大可轮转归档 |
| 主 agent 自己探查结论异常 | 先核对目录（`pwd` / `-C <路径>`）再下结论 |
| 正文打印派单 XML / SendMessage malformed | 失准前兆：立刻停手，回干净三参数工具调用，以最新工具调用真实回执为准 |
| 用户报"修复未生效" | 先查部署（比对构建产物内容哈希 vs 源码，别用构建时间）再查代码 |

## git-ops 收口

复用 [[ta]] 的 git-ops 常驻收口专员，唯一有权 commit/push 的 agent。tabb 特有点：**从 journal.md 的 `[DONE]` 行读改动清单**，白名单提交（只 add 点名文件，`diff --cached` 核对后再 commit）。`.tabb/` 目录不入库。三步核验（刷指针/fetch 核验远端头/本地远端 ahead=behind=0）、push 前 fetch 禁 force、发版生效条件随回报提醒——全部沿用 ta，不赘述。

## 用户交互口径

同 [[ta]]：先说结论；问进度给列头固定的状态表（任务/agent/进度条/当前阶段，进度条列必填）；设计级/数据/生产决策先拍板再动工（tabb 里这类由 agent 写 `[DECISION]`、主 agent 上抛）；落地声明必须有真实工具回执（rev-parse/grep/TaskOutput），拿不到说"待核实"不编造；用户批评当场纠偏并固化进长期记忆。

**要用户拍板的，尽量用交互式选项卡让用户点选，别用纯文字问答。** 凡是需要用户拍板的（agent 上抛的 `[DECISION]`、主 agent 自己遇到的设计级分歧、收口/发版口径等），**只要选项能枚举，就用 AskUserQuestion 那种带推荐项的交互式选项让用户点选拍板**——把每个候选方案连同它的代价/风险做成一个选项、首选项标「（推荐）」放最前。这比让用户读一段文字再打字回复省事、也更不容易漏掉关键取舍。只有选项确实无法枚举（开放式设计、要用户给具体数值/路径）时，才退回文字提问。上抛前该给的事实（如 `[DECISION]` 里的影响面、脏数据行数、回滚代价）仍要摆全，选项卡是承载它们的形式，不是省略它们的借口。

## Common Mistakes

| 错误 | 后果 | 正解 |
|---|---|---|
| 幻想 agent 互相 spawn / 纯 mesh | 原语不支持，硬试失败空耗 | 去中心化只在协调层；派单层主 agent 仍是唯一 spawner |
| 不看复杂度一律先派 scout、无脑 scout→impl 两跳 | 不复杂的任务白搭一次交接，慢且啰嗦 | 铁律二：不复杂就派一个 general-purpose 一站式查+改+验；两跳只留给复杂任务（大但不复杂→拆并行一站式，不是 scout→impl） |
| 主 agent 又去中转 agent 间协调 | 退化回 ta 主从，黑板白建 | 协调走黑板；主 agent 只在上抛用户/回收异常时介入 |
| 往 board.md 里塞正文（根因/改动细节） | 文件膨胀、读入 token 变多 | board.md 只放认领指针；正文进 journal.md |
| 改文件不走锁协议直接 Edit | 并行 agent 互盖、改动丢失 | 改文件前必 `mkdir .tabb/locks/<F>` 抢锁，GOT 才动手 |
| 抢锁还去改共享锁表 / 回读比时间戳 | 多一半工具往返，还留 TOCTOU 竞态 | 用 `mkdir` 原子锁，一条 Bash 抢、一条 Bash 放；别退回旧乐观锁表 |
| 锁了文件干完不放（攥着锁目录） | 别的 agent 一直 BUSY、被无谓阻塞 | 锁只在 Edit 窗口内持有，干完立即 `rm -rf` 锁目录 |
| 完工写了 journal 就 idle、不 return 回报 | 主 agent 只能来催，白费一轮（tabb 高发） | 写 journal ≠ 回报；干完必以一条 return 回报主 agent，别 idle 停住 |
| agent 撞决策自裁不上抛 | 设计/数据/生产被 agent 擅改 | 写 `[DECISION]` 停下，主 agent 上抛用户 |
| 主 agent 忘了轮询 journal 的 `[DECISION]` | 决策悬空，agent 卡死等回话 | 每次回报循环先扫 `[DECISION]`，有就立刻上抛 |
| 主 agent 顺手改代码/跑收口 | 上下文膨胀、与 agent 撞车 | 一律派单，铁律无豁免 |
| 为"建黑板文件"专门派 bootstrap agent | 多此一举，凭空多一跳 | 建/维护 `.tabb/` 是铁律例外，主 agent 自己建；只有动仓库业务文件才派单 |
| 主 agent 把 `[HANDOFF]` 正文复述进下游派单 | scout 正文抄进主上下文，污染 + 冗余 | 主 agent 只当门禁放行 + spawn；下游派单只点"去 journal 读那条 `[HANDOFF]`"，让它自己读 |
| 下游任务一开始就播成 open | 下游 agent 一 spawn 就空转抢没就绪的活 | 有依赖的先播 `blocked:等[HANDOFF]xxx`，门禁触发再提为 open |
| 派单不带里程碑清单 / 协议块里省了里程碑行 | agent 不打 `【里程碑 N/总 ✓】` 标记，主 agent 无信号渲染进度条 | 协议块里的「里程碑」行必填并填成具体清单，要求 agent 每跨段打标记 |
| 进度表省掉进度条列 / 用「阶段+状态」文字顶替 | 违反格式契约，用户看不到分段进度 | 列头恒为 任务/agent/进度条/当前阶段，进度条列必填；拿不到标记就填 `？/？ 无里程碑信号` 并回补，绝不整列省略或改成文字表 |
| 给用户报平滑百分比进度条 | subagent 没连续完成度信号，是编造 | 只报分段式（点亮到最新里程碑标记那段） |
| SendMessage 带三参数以外字段 / 正文复述 message | malformed 诱发主上下文污染失准；刷屏 | 只带 `to`/`summary`/`message`；每单登记一行 |
| `.tabb/` 被 git add 入库 | 协调产物污染仓库历史 | init 时加进 `.gitignore` |

## 选型：什么时候用 tabb，什么时候用 ta

**第一判据是文件冲突协调的频度**，不是任务数量：

- **多 agent 高频并行改同一仓、公共文件反复被撞、每次协调避让都拖累主 agent** → 用 `/tabb`。这是 tabb 的硬内核（去中心化文件避让），也是它相对 ta 唯一质变的地方。
- **交互式持续派单、需要主 agent 维护干净全局台账、但任务间文件冲突不频繁** → 用 `/ta`（主从星型，主 agent 集中裁决，简单可控）。任务认领 / 决策上抛 / 交接这些 ta 配合通用能力也能做得不差，别只为这几块上 tabb。

黑板不是免费的：它引入轮询延迟、需要清道夫兜死锁与 idle 不回报，实测还比 ta 慢一截、多烧 token（文件锁已用 `mkdir` 原子化、不再靠回读，但任务队列仍是非原子读改写）。**只有当"主 agent 成了文件协调瓶颈"这个痛点真实且高频时，这些代价才换得回来**，否则 ta 更省心。
