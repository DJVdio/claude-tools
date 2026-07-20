---
name: tabb
description: 去中心化黑板多 agent 编排。仅由 /tabb 手动触发。适合多个 agent 并行改同一仓、需自助认领任务和原子避让文件冲突的场景；协调走共享文件，主 agent 只负责派单、门禁、用户交互和收口。
---

# Agent Team 黑板编排（tabb）

## 适用边界

tabb 的硬价值：多个 agent 并行改同一仓时，用 `.tabb/locks/` 原子文件锁自助避让覆盖。若文件冲突不频繁，优先 `/ta`；黑板会增加轮询、清道夫和 token 成本。

tabb 独立可安装，不依赖 ta 文件或正文。ta 仅用于选型对比。

通信原语只有：主 agent spawn / 发消息、子 agent return、所有 agent 共享文件系统。没有子 agent 互相寻址或 spawn。因此：

- 协调去中心化：认领、锁、交接走黑板。
- 派单仍中心化：主 agent 是唯一 spawner。

## 三条铁律

1. **主 agent 不做业务任务。** 读改代码、测试、git 都派 worker；主 agent 只编排、维护 `.tabb/`、轻量只读核实、对用户汇报。修改 `.gitignore` 也属业务文件，派 worker。
2. **按复杂度决定跳数。** 默认一个 general-purpose worker 一站式查→改→验。大但清晰：拆并行一站式任务。只有链路/根因不明，且侦察结论供多个下游复用时，才 scout→`[HANDOFF]`→impl。
3. **路由只认固定五档。** 不参考主 agent 档位，不临场升降；必须运行路由脚本并照输出派发。tabb 不使用 OpenCode，所以只读固定为 Luna-low。

### 模型与 effort 路由

| 类别 | 判定 | 固定路由 |
|---|---|---|
| `readonly` | 零业务写入，只查代码、日志、资料、调用链 | `gpt-5.6-luna / low` |
| `simple` | 方案明确、修改机械、低风险；规模大仍可属此档 | `gpt-5.6-luna / medium` |
| `complex-short` | 需要明显推理或取舍，但问题边界与验证路径清楚 | `gpt-5.6-luna / max` |
| `complex-long` | 推理本身复杂，且存在紧耦合跨模块因果、多方案深度取舍，或无法安全拆分的长链路 | `gpt-5.6-sol / medium` |
| `very-complex` | 跨系统架构、根因高度不明、安全/一致性关键或错误代价极高 | `gpt-5.6-sol / high` |

### 分类顺序与升档门禁

1. **先拆单，后分类。** 先把用户总需求拆成能独立实现、验证的一站式任务卡，再分别判档；禁止按原始总需求的体量给每张卡升档。
2. **规模只决定拆单，不决定模型。** 文件多、步骤多、预计耗时长、测试慢，都不是 `complex-long` 证据。大但清晰的任务应拆成多个 `simple` 一站式小单。
3. **Sol 必须有具体理由。** 选 `complex-long` / `very-complex` 时，`[ROUTE]` 理由必须写明哪个推理难点不能通过继续拆单消除；只能写出“文件多/耗时长/需一站式”时不得上 Sol。
4. **无复杂证据不上调。** 相邻档拿不准时，若没有上述具体复杂信号，按较低档；不得因“一站式”默认预留能力。

例：同一字段机械同步到 8 个页面并补测试，拆成几张 `simple`；需同时重构状态机、保持兼容性并在多种竞态方案间取舍，才可判 `complex-long`。不得自创第六档，也不得修改固定模型或 effort。

## 黑板契约

```text
.tabb/
  locks/        # 每个被改文件一个原子锁目录
  board.md      # 小型任务队列，只放认领指针
  journal.md    # append-only 事件日志
  assignments.tsv # task/agent/role/model/effort 追加式登记
  sealed.log    # seal-from-journal.sh 的成功记账
```

### board.md

```markdown
## 任务队列
| 任务 | 认领者 | 状态 |
|---|---|---|
| 修登录鉴权 | impl-auth | doing |
| 加店铺列表 | — | open |
```

正文不得进入 board；根因、改动、决策、交接都写 journal。有依赖的下游先标 `blocked:等[HANDOFF]xxx`。任务认领后必须回读；认领者不是自己则让位。

### journal.md

```markdown
[DONE] impl-auth | 修登录鉴权 | 根因 src/auth.ts:42 | 改 auth.ts,login.ts | 定向测试红→绿 | 无遗留
[SEAL] /repo/web | sub | main | src/auth.ts,src/login.ts | fix(web): 修登录鉴权
[HANDOFF] scout-signup → impl-signup | 注册走 api/signup.ts，校验在 validators.ts:88
[DECISION] impl-billing | 是否清理 2023 年前生产脏数据？
```

- 实现/测试任务：释放所有锁后写 `[DONE]` + `[SEAL]`，两行缺一不可。
- 纯只读交接：写 `[HANDOFF]`，不写 `[SEAL]`。
- `[DONE]` 给人读，可保留有价值的根因分析；`[SEAL]` 给脚本读，必须单行、字段准确。
- journal 完工记录是权威状态；worker 的 `【RETURN】` 是会话镜像，不是第二道完成门禁。

### 原子文件锁

锁的是文件，不是任务。改文件 `F` 前：

```bash
L=.tabb/locks/$(printf '%s' "F" | sed 's#/#__#g')
mkdir "${L}" 2>/dev/null && { printf '%s %s\n' "<agent-id>" "F" > "${L}/meta"; echo GOT; } || echo BUSY
```

- `GOT`：独占 F，才可改。
- `BUSY`：拉其他 open 任务，稍后重试；禁止等锁空转。
- 不加时间戳、不用 Python；`mkdir` 已保证原子性，锁龄读目录 mtime。

改完立即放锁：

```bash
rm -rf "${L}"
```

## 主 agent 流程

1. 建 `.tabb/locks/`、board 表头、journal、assignments；把 `.tabb/` 加入 `.gitignore` 的工作派给 worker。
2. 拆并行任务写入 board；明确依赖，未成功 spawn 的任务保持 `open` / `blocked`，不得先标 `doing`。
3. 先运行固定路由脚本；输出为 `pool<TAB>model<TAB>effort`，必须原样用于登记，并按下述显式覆盖/父模型继承规则派发：

   ```bash
   python3 <skill-dir>/scripts/route-task.py --class <readonly|simple|complex-short|complex-long|very-complex>
   bash <skill-dir>/scripts/register-assignment.sh --repo "<仓库绝对路径>" \
     --task "<task>" --agent "<agent>" --role "<readonly|simple|implementation|git-ops>" \
     --model "<脚本 model>" --effort "<脚本 effort>"
   ```

4. 为每个 worker 嵌入下节完整协议。登记失败不得 spawn，也不得手写 assignments 绕过脚本。spawn 成功后才把 board 改为 `doing`；失败则改为 `blocked:<真实错误>`，禁止面板虚报在途。
5. 轮询 locks、board、journal 和在途 agent 里程碑：
   - `[DECISION]`：立即带推荐方案上抛用户；裁决写回 journal。
   - `[HANDOFF]`：放行对应 blocked 任务。派单只叫下游自行读该条，不复述正文。
   - `[DONE]+[SEAL]` / `[HANDOFF]`：更新完成状态；锁已释放即可推进。
6. worker 全部完成后关闭它们，释放并发槽；创建唯一 git-ops，按任务类别路由后跑全量验证，PASS 才 seal。
7. 从真实回执汇报结果；不凭记忆宣称完成、提交、推送或生效。

### Premium spawn 模型传递

路由脚本给出的 model/effort 是**目标实际运行档**；spawn 参数只是把它传给调度器的方式。派发前先读当前 spawn 工具声明的可显式覆盖模型，不用一次必然失败的调用做探测。

- **显式覆盖：**目标模型在工具 allowlist 中，显式传脚本给出的 `model` 和 `reasoning_effort`。
- **父模型继承：**目标模型不在 allowlist，但确认它就是当前主 agent 模型时，spawn **省略 `model`** 以继承当前模型；若工具允许独立覆盖 effort，仍传脚本的 `reasoning_effort`。Codex 中传 effort 时用 `fork_turns="none"` 或正整数，不用会强制全量继承 effort 的 `all`。
- **不可用：**目标模型既不能显式覆盖，也不是当前主模型（或目标 effort 也无法精确传递）时，在 spawn 前阻塞并如实报告。禁止改传 Sol/Terra 或其他模型。

父模型继承是同一目标模型的合法传递，不是静默替换。assignments 仍登记脚本的目标 model/effort；给用户的派单回执注明 `explicit` 或 `inherit-parent`，不把 UI 可选列表误当成 spawn allowlist。

主 agent 不转述 agent 间协调内容。派单正文只进工具调用；给用户登记一行：`→ 已派 impl-auth：修登录鉴权（黑板协调）`。若 harness 使用 `SendMessage`，只传 `to` / `summary` / `message`；禁止手写 `<invoke>` / `<parameter>` 或附加字段。出现 malformed 立即停，回到合法工具调用，以真实回执为准。

## Worker 派单协议块

每张派单必须原样包含以下能力，可替换占位符、按任务删掉不适用分支，但不得删门禁：

```text
【tabb 协议】
仓库：<绝对路径>；分支：<目标分支>；你的 id：<agent-id>。
调度：class=<五档类别>；model=<脚本 model>；effort=<脚本 effort>；role=<readonly|simple|implementation|git-ops>。
黑板：<仓库>/.tabb/board.md、journal.md、locks/。
只改工作区，不 commit/push；git-ops 统一收口。

任务：<用户口径原话>。
输入：<已知结论；若有 HANDOFF，只写“自行读 journal 中对应 HANDOFF”>。
边界：<禁改文件/其他 agent 范围>。
验证：先写复现测试红，再修绿；只跑 <定向命令>。既有失败白名单：<基线>。不得跑或声称通过全量测试。
里程碑：<3-5 个具体阶段>；每完成一段输出 `【里程碑 N/总 ✓ 阶段】`。

改文件 F 前原子抢锁：
  L=.tabb/locks/$(printf '%s' "F" | sed 's#/#__#g')
  mkdir "${L}" 2>/dev/null && { printf '%s %s\n' "<agent-id>" "F" > "${L}/meta"; echo GOT; } || echo BUSY
GOT 才改；BUSY 就拉别的 open 任务，稍后重试，禁止空转。改完立即 `rm -rf "${L}"`。不要加时间戳或 Python。

手头任务完成后可去 board 认领 open 任务：写入后回读；成功便复制自己的 agent/role/model/effort、仅替换 task 后 append assignments.tsv，失败则让位。
复杂结论写 `[HANDOFF] <你> → <下游> | <要点，带 file:line>`。
设计语义、数据写、生产写不得自裁：写 `[DECISION] <你> | <问题>` 后停等裁决。

释放全部锁后留痕：
- 实现/测试写：
  `[DONE] <你> | <任务> | 根因 file:line | 改动 | 定向测试红→绿 | 遗留`
  `[SEAL] <仓绝对路径> | <子模块或 -> | <分支> | <相对文件,逗号分隔> | <commit msg>`
- 纯只读交接只写 `[HANDOFF]`，不写 `[SEAL]`。

最后一条 assistant 回复必须以 `【RETURN】` 开头，含根因 file:line、改动、定向测试证据、遗留、里程碑 N/N。`return` 是最终回复，不是 Bash 或 journal 标签。无 open 任务且不等锁时，回报后结束，禁止 idle。
```

派单另须明确：仓库绝对路径、目标分支、用户口径原话、已知假设（先核实）、定向验证命令与基线、其他 agent 的文件边界。侦察单注明只读。含糊口径必须 `[DECISION]`，不得自由发挥。

## 轮询、进度与异常

持续回报用 `ScheduleWakeup` 约每 270 秒自续排；每轮读 locks/board/journal，再从在途 agent 的 `TaskOutput` 取最新里程碑。仍有人工作则续排；全员结束且无 open 任务时停止。进度只能按最新里程碑分段显示，如 `■■■□ 3/4`；无信号写 `？/？ 无里程碑信号` 并补发里程碑要求，禁止编平滑百分比。

用户问“进度如何”“看看任务面板”“任务面板”或“谁在做什么”时，立即运行并原样展示下表；不得遗漏 open/blocked 任务，随后再补真实里程碑：

```bash
bash <skill-dir>/scripts/task-panel.sh --repo "<仓库绝对路径>"
```

面板固定含 `Task / Agent / Role / Model / Effort / State`；未派发显示 `not-dispatched`，在途任务出现 `unregistered` 就先补登记，不得猜测。

| 情况 | 处置 |
|---|---|
| `BUSY` | 拉其他 open 任务，稍后重试 |
| 超龄锁 | `find .tabb/locks -maxdepth 1 -mindepth 1 -type d -mmin +10`；确认 meta 持有者已 idle/失联后删锁、任务退回 open、派接替者 |
| 完工记录齐但缺 `【RETURN】` | 继续推进；无 `[RETURN_REQUESTED]` 才补催一次并记账，禁止重复催或 respawn |
| 连续 2-3 次 idle | 仅在完工记录不齐、仍持锁或工作区/测试未完成时接替；记录齐则视为完成 |
| 两 agent 认领同任务 | 回读失败者让位；主 agent 巡检去重 |
| board 膨胀 | 正文移到 journal；必要时轮转 journal |
| `[DECISION]` | 立即上抛用户，不积压 |
| SSH/远端瞬时失败 | commit 若已在本地则只重试 push；持续失败如实报告，禁止重跑整条流水线 |
| 用户称修复未生效 | 先比对构建产物与源码内容哈希，再查代码 |

## 全量验证与 git-ops 收口

并行期每个 worker 只跑定向测试。收口顺序不可变：

1. 所有实现任务 `[DONE]+[SEAL]` 齐、只读任务 `[HANDOFF]` 齐、锁全释放。
2. 关闭完成 worker，释放槽位；再建唯一 git-ops。
3. git-ops 在合并工作区跑项目真实全量测试，追加本批次新的 `[VERIFY] ... | PASS/FAIL ...`。不得复用旧 PASS。
4. 仅本批次 `[VERIFY] PASS` 可 seal；FAIL 或缺记录时禁止 commit/push，派修复 worker 后重跑验证。

git-ops 不常驻，是唯一可 commit/push/合并/刷子仓指针的 agent。先核验分支、远端同步、worktree、脏文件；未点名文件不动；禁 force push。目标分支被占用时用临时 worktree，结束后清理。

白名单只读 `[SEAL]`，禁止从 `[DONE]` 自由文本提炼。漏 `[SEAL]` 就让原 worker 补。预检与落地：

```bash
bash ~/.claude/skills/tabb/seal-from-journal.sh --dry-run
bash ~/.claude/skills/tabb/seal-from-journal.sh
```

脚本会抽取/去重 `[SEAL]`、跳过 `sealed.log` 已成功项、按仓聚合并并发调用 `seal.sh`。失败后重跑同一命令：成功仓跳过；本地已 commit 但未 push 的失败仓续推。

`seal.sh` 强制白名单、真实 `rev-parse`、push 前 fetch、远端前移时安全 rebase、冲突 abort、禁 force、子仓先推再刷父仓指针、最终核验远端 sha 与 ahead/behind。一个仓失败不阻断其他仓，也不丢其改动/stash。

收口回报用 `修复 / commit sha / 生效动作` 表；明确推送不等于部署，列出实际构建、部署、上传或流水线动作。

## 用户交互

- 先给完成项或根因，再给证据。
- 设计语义、清改数据、生产写、不可逆动作先拍板；可枚举时给带推荐项的选项与风险。
- 生产数据写先 SELECT 统计、备份、回滚 SQL，并展示 SQL 与影响行数，获批后执行。
- 用户离开时，只推进可回退且符合既定意图的动作；新授权或不可回退动作挂起。

## 收尾自检

- 主 agent 是否只编排，未碰业务代码/git？
- 每个改文件是否用 `mkdir` 锁并及时释放？
- board 是否只放指针，journal 是否具备正确完成记录？
- 缺 return 时是否只补催一次、未重复 spawn？
- worker 是否只跑定向测试，本批次是否有新 `[VERIFY] PASS`？
- git-ops 是否只从 `[SEAL]` 取白名单并走 `seal-from-journal.sh`？
- 用户看到的进度是否来自离散里程碑和真实回执？
- 每个任务是否先跑固定路由脚本，并登记、展示、派发同一组精确 model/effort？
