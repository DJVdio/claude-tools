# tabb — 去中心化黑板编排 skill 设计

> 状态：已落地 `skills/tabb/SKILL.md` 并跑完 skill-creator 行为基准（2026-07-10）。基准与修正见文末「验证结果」。

## 背景

ta 当前是**星型/主从（hub-and-spoke）**编排：主 agent 是唯一路由中枢，所有 subagent 彼此不通信，一切协调过主 agent 中转。主 agent 因此成为协调瓶颈，也承担了被代码细节污染编排位的风险。

tabb 探索另一种拓扑：**去中心化黑板（blackboard）**——agent 之间的协调不过主 agent，而是通过文件系统上的共享黑板完成。

## 硬约束（决定拓扑上限，必须写进 skill）

Claude Code harness 的 agent 间通信原语只有：
1. 主 agent `spawn` 子 agent（单向下发）
2. 主 agent `SendMessage` 给在途子 agent（单向补料/催报）
3. 子 agent `return` 最终结果给主 agent（单向上报）
4. **所有 agent 共享同一文件系统**（除非 worktree 隔离）

**没有「子 agent → 子 agent」这条边**：子 agent 不知道兄弟名字、无寻址权限、被 dispatch 时还被要求忽略编排 skill。

结论：真·pub/sub 推送总线做不到；纯 mesh 做不到。能落地的只有 **黑板 over 共享 FS + 轮询**。

## 定位

tabb = 独立的去中心化编排 skill，和 ta 平级，`/tabb` 手动触发、不自动触发。

**一句诚实边界（写死在 skill 里）**：本 harness 里「去中心化」只发生在**协调层**，不在**派单层**——主 agent 仍是唯一 spawner。主 agent 从「消息路由中枢」降级为：**黑板管理员 + spawner + 用户接口 + 收口驱动**。agent 间协调交给黑板，不再过主 agent 中转。

## 黑板物理布局（冷热拆分）

```
.tabb/
  board.md      ← 热索引，刻意保持极小，唯一的临界资源
  journal.md    ← 冷日志，append-only，按需读，可轮转
```

拆分动机：单一大黑板文件会让「写后回读校验」的乐观锁自旋变慢、临界资源争用变重。把**被争用的锁/认领元数据**（小、热）与**批量内容**（大、冷、append-only 天然不争）分离，是黑板能撑住的胜负手。

- **board.md（热、被抢）**：只放两张小表
  - **文件锁表**：文件 → 持有 agent → 状态 → 时间戳
  - **任务认领表**：任务 → 认领者 → 状态
- **journal.md（冷、不抢）**：append-only。每个 agent 只 append 自己的行，天然不争用。承载：
  - 完工广播 + 交接要点（根因 file:line / 改动清单 / 遗留决策点）
  - 待用户拍板条目

## 认领协议（board.md 上的乐观锁）

1. 动任何文件前，读 board.md
2. 目标文件未锁 → append 一行锁记录（agent-id + `date +%s%N` 取的单调标记）
3. **回读校验**：自己的行完好，且是该文件**最早**的认领（时间戳 + agent-id 做 tie-break）→ 持锁开工
4. 若存在更早认领 / 自己的行被覆盖 → 退避，改拉别的任务或等待，重试
5. 完工 → board.md 标锁释放，journal.md append done + 交接要点

## 四区块职责

| 区块 | 在哪 | 谁写 | 谁读 |
|---|---|---|---|
| 文件锁 | board.md | 干活 agent | 所有 agent（动文件前） |
| 任务认领队列 | board.md | 空闲 agent 自助拉（pull 模型） | 所有 agent |
| 完工广播 / 交接 | journal.md | 完工 agent | 下游依赖 agent + 主 agent |
| 待用户拍板 | journal.md | 撞到设计/数据/生产决策的 agent | 主 agent 轮询 → 上抛用户 |

## 主 agent 残余职责

init 黑板（建 `.tabb/board.md` + `journal.md`）→ 播种任务队列 → spawn worker（每张派单内嵌「tabb 协议块」）→ 轮询 journal 的待拍板条目上抛用户 → 按 done 广播驱动 git-ops 收口 → 用户可见的进度汇报。**不再路由 agent 间协调**——那是黑板的活。

## 派单 prompt 的「tabb 协议块」

每个 worker 注入：黑板路径 + 认领协议五步 + 「动文件先轮询、锁、校验、放锁」+「空闲自助拉队列」+「完工写 journal」+「设计/数据/生产决策写待拍板、不自裁」。

## 异常与兜底

| 症状 | 处置 |
|---|---|
| 抢锁失败（竞态） | 协议内退避重试，改拉别的任务 |
| 死锁（agent 挂了还占锁） | 主 agent 当黑板清道夫：发现锁被 idle/失联 agent 超时占用 → 回收/改派 |
| 并发写把 board 写花 | 回读校验兜住，agent 重写自己那行 |
| board 膨胀 | 设计上 board.md 恒小；journal 可轮转 |

## 进度汇报

主 agent 从 board（谁持什么锁、任务认领状态）+ journal（done 行）渲染进度，复用 ta 的分段里程碑进度条口径（无平滑百分比）。

## 收口

复用 ta 的 git-ops 常驻收口专员：done 广播累积到批次阈值或用户说「收口」时触发，从 journal 读改动清单做白名单提交。

## 落地方式

skill-creator 建 `tabb` skill，产出 `skills/tabb/SKILL.md`，风格对齐现有 ta（铁律 / 角色表 / Common Mistakes）。用 skill-creator 的 eval 能力跑协议场景验证描述触发准确度。

## 与 ta 的关系（给用户的选择口径）

- 交互式持续派单、需要主 agent 维护干净全局台账 → 用 `/ta`（主从星型）
- 高频文件冲突协调拖累主 agent、想让 agent 自助避让 → 用 `/tabb`（去中心化黑板）

## 验证结果（skill-creator 行为基准，iteration-1）

3 个组队场景，各跑 with-skill（读 tabb）vs baseline（无 skill）产出编排方案，按客观断言打分。

| 场景 | with-skill | baseline | 区分度 |
|---|---|---|---|
| 文件争用（认领协议） | 6/6 | 0/6 | 极高——tabb 硬内核 |
| 决策上抛 | 5/5 | 4/5 | 低 |
| 黑板交接 | 5/5 | 4/5 | 低 |
| **合计** | **100% (16/16)** | **53.3% (8/15)** | Δ +0.47 |

时延/tokens：with-skill ~176s / ~31.8k，baseline ~103s / ~20.6k（协议展开成本，可接受）。

**关键洞察**：tabb 唯一不可替代的价值是**文件争用协调**——baseline 用 git worktree 隔离 + lead 单点收敛（与去中心化路线相反，0/6）。决策上抛与交接两场景 baseline 凭通用能力已覆盖七八成（甚至自发发明结构化黑板交接），只缺 tabb 特有的 `[DECISION]`/`[HANDOFF]`/journal 词汇。

**据此对 SKILL.md 的修正（未再跑 eval，属澄清/补充）**：
1. **钉死"谁建黑板"**：主 agent 自己建/维护 `.tabb/` 是铁律例外（编排设施非业务任务），不必派 bootstrap agent；只有动仓库业务文件才派单。此前三个 with-skill agent 对此各自圆场、答案不一。
2. **交接的诚实流程**：主 agent 读 `[HANDOFF]` 只当 spawn 门禁放行信号，不把正文复述进下游派单，让下游自己读 journal——交接**内容**不过主 agent，只有 spawn **门禁**过主 agent。
3. **blocked 播种法**：有依赖的下游任务先播 `blocked:等[HANDOFF]xxx`，门禁触发再提为 open，防止下游空转。
4. **定位收敛**：Overview/选型 改为以"文件争用协调"为第一判据与头号卖点，其余区块降为配套。

## 后续迭代（实跑反馈驱动，2026-07-10）

1. **铁律二补入**：小/不复杂任务一站式 general-purpose，两跳只留给复杂任务；判据是复杂度不是规模。
2. **里程碑进标准派单块**：原先只在散文提"沿用 ta"，落地丢失致进度表退化；已塞进协议块模板本体。
3. **拍板走交互**：需用户拍板的尽量用 AskUserQuestion 带推荐项选项卡。
4. **文件锁改原子 lockfile**（取代本文「认领协议」那节的乐观锁）：`mkdir .tabb/locks/<F>` 抢、`rm -rf` 放，OS 级原子互斥——比"共享锁表 + 回读比时间戳"少一半工具往返、且根除 TOCTOU 竞态。任务队列/journal 保持文件。
5. **idle 不回报兜底**：tabb 加了 journal 输出通道后，scout 常写完 journal 就 idle 不 return；协议块钉死"写 journal ≠ 回报、完工必 return"，回报循环再兜一道催报。
