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

init 黑板（建 `.tabb/board.md` + `journal.md`）→ 播种任务队列 → spawn worker（每张派单内嵌「tabb 协议块」）→ 轮询 journal 的待拍板条目上抛用户 → 批次收口前全量集成验证 → 按 done 广播驱动 git-ops 收口 → 用户可见的进度汇报。**不再路由 agent 间协调**——那是黑板的活。

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

多任务并行时，worker 只跑自身改动相关的定向测试；git-ops 不常驻，所有任务完成且锁释放后先关闭已完成 worker 释放槽位，再创建它，让它先进入 `integration-verify` 阶段，跑项目真实全量测试并追加本批次的 `[VERIFY] PASS/FAIL`。只有本批次新产生的 `[VERIFY] PASS` 才能继续从 journal 读改动清单做白名单提交；缺失、复用旧 PASS 或 FAIL 都禁止 commit/push，避免额外 spawn 验证 agent 撞满并发槽位。

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
6. **修正完工语义**：实现任务用 `[DONE]+[SEAL]`、纯只读交接任务用 `[HANDOFF]` 作为主 agent 可消费的权威持久化完成信号；子 agent 的 `【RETURN】` 最终回复是会话镜像，不再作为阻塞收口的第二个完成条件。补报请求用 `[RETURN_REQUESTED]` 记账去重；只要完工记录齐全，后续 idle 不得触发接替或重复派单。
7. **测试分层**：多任务并行时 worker 只跑定向测试/最小检查；git-ops 不常驻，批次收口前才创建它并进入 `integration-verify` 阶段统一跑全量测试，写 `[VERIFY] PASS/FAIL` 作为 seal 的提交门禁，避免半成品工作区上的重复全量测试和额外 agent 撞满并发槽位。

## 性能调研：黑板该不该搬进内存？（2026-07-14，实测）

**起因**：怀疑"黑板走磁盘"拖慢 tabb，考虑把锁和黑板搬进内存（tmpfs / MCP 常驻 server）。

**结论：前提不成立——锁和黑板本来就在内存里，磁盘不是瓶颈。** 本机 APFS 实测：

| 操作 | 纯磁盘耗时 |
|---|---|
| `mkdir` 抢锁 + 写 meta + `rm` 放锁 | 161 µs |
| 读 board.md（~500B） | 10 µs |
| 读改写 board.md（认领） | 58 µs |
| append journal.md | 27 µs |
| `ls .tabb/locks/` | 8 µs |

- 一条完整抢锁 Bash **本地执行 21 ms**，拆开是：`python3` 冷启动取时间戳 **16.5 ms（78%）**、shell 进程启动 4.5 ms（21%）、**真正的磁盘操作 0.16 ms（0.8%）**。
- 再叠 LLM 往返（逐字生成三行含 `sed` 转义的 shell，上百 output token，秒级），一次抢锁端到端 **3–6 秒**，磁盘占 **0.003%**。搬内存的收益上限约等于零。
- **"读 500B 文件只要 10 µs"本身就是证据**：SSD 随机读至少 50–100 µs，10 µs 只可能来自 page cache。`.tabb/` 的小文件读写全在内核 unified buffer cache 里完成，`mkdir`/`write` 都不 `fsync`，落盘是异步 writeback、不阻塞 agent。**OS 已经免费把黑板放进内存了**，还白送崩溃后状态仍在盘上、`ls`/`cat` 一眼可查的调试能力。

**真正的成本结构**：LLM 工具往返次数 × 秒级往返延迟 + 把黑板读进上下文的 token。两项都与存储介质无关，换介质动不了任何一项。

**据此的修正（已落地 SKILL.md）**：**抢锁协议删掉 `python3` 时间戳**。SKILL.md 自己就写着"锁的正确性只靠 `mkdir` 原子性、死锁判定用锁目录 mtime，都不依赖它"——既然不依赖就是纯浪费，而它吃掉单条抢锁本地耗时的 78%。删后实测 **21.16 ms → 4.66 ms（4.5x）**，同时 LLM 每次少生成一行最易写错的 shell。死锁判定改用 `find .tabb/locks -maxdepth 1 -mindepth 1 -type d -mmin +10`（已验证 macOS 可用）；meta 只留持有者。

**未采纳但机制上可行：MCP 内存黑板。** 实测确认 subagent 的 Bash 与主 agent 的 Bash 挂在**同一个 claude 进程**（ppid 相同）下——subagent 不是独立 OS 进程，所以 stdio MCP server 在 session 启动时连接一次、全体 agent 共享其进程内存，方案成立。但它**省的不是磁盘 I/O，而是工具往返次数与 output token**：把抢锁变成 `lock(file=...)` 结构化调用，把"读 board→改认领者→写回→回读校验"的非原子读改写压成一次原子 `claim_next_task(agent_id)`（顺带根除任务队列 TOCTOU）。代价是 daemon 生命周期管理、崩溃后状态全丢、调试从 `cat journal.md` 退化成翻 MCP 日志。留作后续选项。
