---
name: tabb
description: 去中心化黑板（blackboard）多 agent 编排规则。仅通过 /tabb 手动触发，不自动触发。用于"多个 agent 并行改同一仓、彼此需要自助避让文件冲突与交接信息、不想让主 agent 成为协调瓶颈"的协作形态——agent 通过共享黑板文件轮询协调，而非事事过主 agent 中转。是 ta 主从星型编排的去中心化替代形态。
---

# Agent Team 黑板编排（tabb）

## Overview

把一次会话变成一支**自组织**开发团队：**协调不过主 agent，而是通过文件系统上的共享黑板完成**。主 agent 从"消息路由中枢"降级为**黑板管理员 + spawner + 用户接口 + 收口驱动**；agent 之间靠轮询黑板自助认领任务、自助避让文件冲突、自助交接产出。核心收益：主 agent 不再是每一次跨 agent 协调的必经瓶颈，协调延迟与主上下文负担都下放到黑板。

**tabb 最不可替代的价值是「多 agent 并行改同一仓时的文件争用协调」**——用共享文件锁的乐观认领协议让并行 agent 自助避让互盖，全程零主 agent 介入、零打扰用户。任务认领 / 决策上抛 / 交接这几块是配套（一个够强的模型不装 tabb 也能做个七八成），**唯独"去中心化文件避让"是它区别于 ta 主从编排的硬内核**。选 tabb 的第一判据永远是：**文件冲突协调是否频繁到值得下放**。

**这是 [[ta]] 主从星型编排的去中心化替代形态。** 选型口径见文末。

## 一条诚实的边界（务必内化，别误用）

这个 harness 的 agent 间通信原语只有四条：主 agent `spawn` 子 agent、主 agent `SendMessage` 给在途子 agent、子 agent `return` 给主 agent、**所有 agent 共享同一文件系统**。**没有"子 agent → 子 agent"这条边**——子 agent 不知道兄弟名字、无寻址权限、被 dispatch 时还被要求忽略编排 skill。

所以 tabb 的"去中心化"**只发生在协调层，不在派单层**：

- **协调层去中心化** ✅：谁锁哪个文件、谁认领哪个任务、谁交接给谁——这些走黑板，agent 之间自助解决，不过主 agent。
- **派单层仍是中心化** ⚠️：主 agent 仍是唯一 spawner。别幻想纯 mesh / agent 互相 spawn——原语不支持，硬试只会失败。

**铁律：主 agent 不自己执行任务。** 读代码、改代码、跑测试、跑 git 都派给 subagent；主 agent 只做编排决策、黑板维护、向用户交互，以及为核实实况做的轻量只读探查。任务再小、用户再说"你直接改"，也是派一个 subagent 或先回问口径，绝不自己上手。

**铁律的唯一例外——建/维护黑板本身：** 主 agent **可以直接**创建与维护 `.tabb/board.md`、`.tabb/journal.md`（建目录、写表头、当清道夫修脏行）。这是**编排设施**，不是"业务任务"，不违反铁律，也不必为它派 bootstrap agent（多此一举）。判据一句话：**只要动的是 `.tabb/` 里的协调文件，主 agent 自己来；只要动的是目标仓库的业务代码 / `.gitignore` / 任何会进 git 的文件，一律派单。**（`.tabb/` 加进目标仓 `.gitignore` 这一步属于后者——改的是仓库文件——交给 git-ops 顺手做。）

**铁律二：跳数匹配规模，小任务一站式，别无脑 scout→impl 两跳。** 黑板机制（尤其 `[HANDOFF]` 交接）容易让人误以为"标准姿势=先派 scout 摸链路、写 HANDOFF、再派 impl 接"——**不是**。派单形态要随任务大小伸缩：

- **小 / 独立任务 → 派一个 general-purpose agent 一站式**：它自己 pull 任务 → 走认领协议锁文件 → 就地查+改+验 → 写 `[DONE]`，**全程不拆 scout、不写 `[HANDOFF]`**。两跳既慢，又平添一次交接。
- **大 / 复杂任务、且摸清结论要喂给多个并行下游 → 才展开 scout→impl 两跳**，用 `[HANDOFF]` 交接（这才是招牌案例的适用场景）。
- **伸缩下限是"一个 subagent"**，不是"凡事先 scout"。拿不准就默认一站式；只有当侦察产物明显要被多个下游复用时，才值得独立 scout。

一句话：`[HANDOFF]`/scout 是**大任务**的工具，不是每单默认动作。队列里一个能一站式吃掉的小任务，就派一个 general-purpose agent 吃掉，别拆。

## 黑板物理布局（冷热拆分是胜负手）

```
.tabb/
  board.md      ← 热索引，刻意保持极小，是唯一被争用的临界资源
  journal.md    ← 冷日志，append-only，按需读，可轮转
```

**为什么拆**：单一大黑板文件会让乐观锁的"写后回读校验"变慢、争用变重。把**被争用的锁/认领元数据**（小、热、频繁读写）和**批量内容**（大、冷、天然不争）分离——board.md 恒小，回读校验才快、竞态窗口才短。这是黑板在无原子写的 harness 里能撑住的关键。

### board.md（热、被抢）—— 只放两张小表

```markdown
## 文件锁
| 文件 | 持有 agent | 状态 | 标记(ns) |
|---|---|---|---|
| src/auth.ts | impl-auth | held | 1720579200123456789 |

## 任务队列
| 任务 | 认领者 | 状态 |
|---|---|---|
| 修登录鉴权 | impl-auth | doing |
| 加店铺列表 | — | open |
```

保持极小：只放锁与认领的**指针**，任何正文（根因、改动、交接细节）都不进 board.md，进 journal.md。

### journal.md（冷、不抢）—— append-only

每个 agent 只 append 自己的行，天然不争用；主 agent 和下游 agent 按需读。三类条目，用 tag 前缀区分：

```markdown
[DONE] impl-auth | 修登录鉴权 | 根因 src/auth.ts:42 空指针 | 改 auth.ts+login.ts | 测试红→绿 | 无遗留
[HANDOFF] scout-signup → impl-signup | 链路摸清：注册走 api/signup.ts，校验在 validators.ts:88   ← 这是大任务的 scout→impl 形态；小任务别照抄，直接一站式（见铁律二）
[DECISION] impl-billing | 是否清理 2023 年前的废弃订单数据？涉及生产写，待用户拍板
```

## 认领协议（board.md 上的乐观锁）

无原子写 / 无文件锁，所以用"乐观锁 + 回读校验 + 冲突重试"兜竞态。**动任何文件前，走这五步**：

1. **读** board.md
2. 目标文件在文件锁表里**未锁** → 用精确 Edit **append 一行锁记录**：`| <文件> | <自己 agent-id> | held | <date +%s%N 取的纳秒标记> |`
3. **回读校验**：重新读 board.md，确认①自己那行完好没被覆盖，②自己是该文件**最早**的认领者（先比标记数值，相等再比 agent-id 字典序做 tie-break）
4. **判定**：是最早 → 持锁开工；不是最早 / 自己的行被写花 → **退避**，回队列拉别的 open 任务，稍后重试这个文件
5. **完工放锁**：把该行状态改 `released`（或删行），并向 journal.md append 一条 `[DONE]`

关键点：**锁的是文件，不是任务**。同一任务可能顺次锁多个文件；锁只在真正 Edit 某文件的窗口内持有，干完立刻放，别攥着不放拖死别人。

## 四区块怎么协同

| 区块 | 在哪 | 谁写 | 谁读 | 作用 |
|---|---|---|---|---|
| 文件锁 | board.md | 干活 agent | 所有 agent（动文件前必读） | 并行 agent 自助避让互盖 |
| 任务队列 | board.md | 主 agent 播种；空闲 agent 认领 | 所有 agent | pull 模型：空闲 agent 自助拉活，不靠主 agent 逐个 push |
| 完工/交接 | journal.md | 完工 agent | 下游依赖 agent + 主 agent | agent→agent 间接交接：下游轮询到 `[HANDOFF]` / `[DONE]` 就接着干 |
| 待用户拍板 | journal.md | 撞到设计/数据/生产决策的 agent | 主 agent 轮询→上抛 | agent 不自裁，写 `[DECISION]` 挂起，等主 agent 上抛用户回话 |

## 主 agent 职责（残余，但关键）

1. **init 黑板**：会话组队即**自己建**（属铁律例外）`.tabb/board.md`（两张空表 + 表头）和 `.tabb/journal.md`；`.tabb/` 加进目标仓 `.gitignore` 这步改的是仓库文件，派 git-ops 顺手做。
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

文件避让（每次 Edit 某文件前走五步）：
  1. 读 board.md
  2. 该文件未锁 → append 一行：| <文件> | <你的id> | held | <运行 date +%s%N 取的纳秒标记> |
  3. 回读 board.md，确认你那行完好、且你是该文件最早认领者（比标记数值，相等比id字典序）
  4. 是最早→开改；不是/被覆盖→退避，回队列拉别的 open 任务，稍后重试
  5. 改完→把该行改 released，向 journal.md append 一条 [DONE]

拉活（pull）：干完手头任务，去 board.md 任务队列认领下一个 open 任务（把认领者改成你、状态改 doing）。
交接：产出对下游有用的结论时，向 journal.md append [HANDOFF] <你> → <下游> | <要点带 file:line>。
决策上抛：撞到设计语义/数据写/生产写决策，别自裁——向 journal.md append [DECISION] <你> | <问题>，停下等主 agent 回话。
回报格式：给主 agent——根因 file:line、改动清单、测试证据(红→绿)、遗留点、里程碑全过 N/N。
```

其余派单要素沿用 [[ta]] 的 impl 类标准：口径原话、已知侦察结论、先红后绿、验证命令与基线白名单、里程碑清单（每跨段打 `【里程碑 N/总 ✓ 语义】`）。

## 派单落地：只发工具调用，不复述正文

同 [[ta]] 的硬约束，一字不改：

- **SendMessage 只带 `to` / `summary` / `message` 三个参数**，多带字段会 malformed，malformed 是主上下文污染失准的起点。
- **message 全文只进工具调用，不抄进给用户的可见输出**。给用户每张派单只登记一行——`→ 已派 impl-auth：修登录鉴权（黑板协调）`。
- **正文永远不贴派单原文 / 完整 prompt / 子 agent 产出**；用户要看细节点开底部 agent 面板或看 TaskOutput。

自查红线（出现任一条即停，回到干净三参数工具调用）：正文冒出 `<invoke>` / `<parameter>` 字样；SendMessage 带了三参数以外的字段；你在正文"描述/排版"一次派单而不是直接作为工具调用发出。

## 定期回报循环

用户要求持续回报时，用 ScheduleWakeup 建自驱循环（间隔约 270 秒，prompt 自带续排逻辑）。tabb 的每次醒来比 ta 多一步"读黑板"：

- **读 board.md** 掌握锁占用与任务队列 → **读 journal.md 新增行**（`[DONE]` 定位完工、`[DECISION]` 定位待上抛、`[HANDOFF]` 掌握交接）→ 轮询各在途 agent 的 `TaskOutput` 扫里程碑标记 → 给超一个周期没消息的 agent 补催。
- 有 `[DECISION]` 未上抛 → **立刻上抛用户**，别攒着。
- 给用户输出**进度表带分段进度条**（任务 / agent / 进度条 / 当前阶段），进度条列必填，渲染与 fallback 同 [[ta]]（点亮到 agent 最新里程碑标记那段，拿不到标记填 `？/？ 无里程碑信号` 并回补）。
- 用户随时问"进度如何" → 即时刷一次。
- 仍有 agent 在工作 → 再排下一次；**全员空闲且任务队列无 open → 输出最终状态，停止循环**。

## 异常处理手册

| 症状 | 处置 |
|---|---|
| 抢锁失败（回读发现别人更早） | 协议内既定：退避，回队列拉别的 open 任务，稍后重试该文件 |
| 死锁（agent 挂了/失联还占着 held 锁） | 主 agent 当**黑板清道夫**：发现某锁被 idle/失联 agent 超时占用 → 把该行改 released 并把任务退回 open，spawn 新 agent 接替（派单交代工作区现状） |
| 并发写把 board.md 写花（表格错行/串行） | 回读校验会兜住——受影响 agent 重写自己那行；主 agent 巡检时修表格结构，别让脏行拖垮后续认领 |
| 两 agent 抢同一 open 任务都改成 doing | 后读者回读发现认领者不是自己 → 让位，回队列拉别的；主 agent 巡检去重 |
| board.md 膨胀 | 设计上恒小（只放指针）；若仍变大是有人往里塞正文——纠正为写 journal。journal 过大可轮转归档 |
| agent 完成没回报就 idle | 消息催要报告（指明要哪些内容） |
| agent 连续 2-3 次 idle 且不响应 | 不再纠缠，spawn 新 agent 接替，派单交代工作区 + 黑板现状；旧 agent 弃用不删；释放它占的锁 |
| 主 agent 自己探查结论异常 | 先核对目录（`pwd` / `-C <路径>`）再下结论 |
| 正文打印派单 XML / SendMessage malformed | 失准前兆：立刻停手，回干净三参数工具调用，以最新工具调用真实回执为准 |
| 用户报"修复未生效" | 先查部署（比对构建产物内容哈希 vs 源码，别用构建时间）再查代码 |

## git-ops 收口

复用 [[ta]] 的 git-ops 常驻收口专员，唯一有权 commit/push 的 agent。tabb 特有点：**从 journal.md 的 `[DONE]` 行读改动清单**，白名单提交（只 add 点名文件，`diff --cached` 核对后再 commit）。`.tabb/` 目录不入库。三步核验（刷指针/fetch 核验远端头/本地远端 ahead=behind=0）、push 前 fetch 禁 force、发版生效条件随回报提醒——全部沿用 ta，不赘述。

## 用户交互口径

同 [[ta]]：先说结论；问进度给列头固定的状态表（任务/agent/进度条/当前阶段，进度条列必填）；设计级/数据/生产决策先拍板再动工（tabb 里这类由 agent 写 `[DECISION]`、主 agent 上抛）；落地声明必须有真实工具回执（rev-parse/grep/TaskOutput），拿不到说"待核实"不编造；用户批评当场纠偏并固化进长期记忆。

## Common Mistakes

| 错误 | 后果 | 正解 |
|---|---|---|
| 幻想 agent 互相 spawn / 纯 mesh | 原语不支持，硬试失败空耗 | 去中心化只在协调层；派单层主 agent 仍是唯一 spawner |
| 不分大小一律先派 scout、无脑 scout→impl 两跳 | 小任务白搭一次交接，慢且啰嗦 | 铁律二：小任务派一个 general-purpose 一站式查+改+验；两跳只留给大任务 |
| 主 agent 又去中转 agent 间协调 | 退化回 ta 主从，黑板白建 | 协调走黑板；主 agent 只在上抛用户/回收异常时介入 |
| 往 board.md 里塞正文（根因/改动细节） | 热文件膨胀、回读变慢、争用加重 | board.md 只放锁与认领指针；正文进 journal.md |
| 改文件不走认领协议直接 Edit | 并行 agent 互盖、改动丢失 | 动文件前必走五步：读→锁→回读校验→判定→放锁 |
| 锁了文件干完不放（攥着锁） | 别的 agent 被无谓阻塞 | 锁只在 Edit 窗口内持有，干完立即 released |
| 回读校验省了，写完就动手 | 竞态没兜住，两 agent 同改一文件 | 回读确认自己那行完好且最早，才开工 |
| agent 撞决策自裁不上抛 | 设计/数据/生产被 agent 擅改 | 写 `[DECISION]` 停下，主 agent 上抛用户 |
| 主 agent 忘了轮询 journal 的 `[DECISION]` | 决策悬空，agent 卡死等回话 | 每次回报循环先扫 `[DECISION]`，有就立刻上抛 |
| 主 agent 顺手改代码/跑收口 | 上下文膨胀、与 agent 撞车 | 一律派单，铁律无豁免 |
| 为"建黑板文件"专门派 bootstrap agent | 多此一举，凭空多一跳 | 建/维护 `.tabb/` 是铁律例外，主 agent 自己建；只有动仓库业务文件才派单 |
| 主 agent 把 `[HANDOFF]` 正文复述进下游派单 | scout 正文抄进主上下文，污染 + 冗余 | 主 agent 只当门禁放行 + spawn；下游派单只点"去 journal 读那条 `[HANDOFF]`"，让它自己读 |
| 下游任务一开始就播成 open | 下游 agent 一 spawn 就空转抢没就绪的活 | 有依赖的先播 `blocked:等[HANDOFF]xxx`，门禁触发再提为 open |
| 给用户报平滑百分比进度条 | subagent 没连续完成度信号，是编造 | 只报分段式（点亮到最新里程碑标记那段） |
| SendMessage 带三参数以外字段 / 正文复述 message | malformed 诱发主上下文污染失准；刷屏 | 只带 `to`/`summary`/`message`；每单登记一行 |
| `.tabb/` 被 git add 入库 | 协调产物污染仓库历史 | init 时加进 `.gitignore` |

## 选型：什么时候用 tabb，什么时候用 ta

**第一判据是文件冲突协调的频度**，不是任务数量：

- **多 agent 高频并行改同一仓、公共文件反复被撞、每次协调避让都拖累主 agent** → 用 `/tabb`。这是 tabb 的硬内核（去中心化文件避让），也是它相对 ta 唯一质变的地方。
- **交互式持续派单、需要主 agent 维护干净全局台账、但任务间文件冲突不频繁** → 用 `/ta`（主从星型，主 agent 集中裁决，简单可控）。任务认领 / 决策上抛 / 交接这些 ta 配合通用能力也能做得不差，别只为这几块上 tabb。

黑板不是免费的：它引入轮询延迟、无原子写、需要清道夫兜死锁，实测还比 ta 慢一截、多烧 token。**只有当"主 agent 成了文件协调瓶颈"这个痛点真实且高频时，这些代价才换得回来**，否则 ta 更省心。
