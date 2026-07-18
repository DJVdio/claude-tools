---
name: taboc
description: 异构模型的去中心化黑板多 agent 编排。仅由 /taboc 手动触发。需要保持或扩大并发，同时把只读、调研、机械性和低风险实现优先交给本机 OpenCode 免费模型，把高风险或高难度任务留给 Codex/Claude 时使用；内置模型与思考档位降级、权限隔离、失败升级和统一收口。
---

# 异构黑板编排（taboc）

## 目标与边界

保持黑板的原子文件锁和统一收口，同时把模型额度当稀缺资源调度：**OpenCode 是默认执行池，高性能 agent 是风险升级池。** 不因“高级模型更稳”而双做同一任务，也不先让高级模型完整侦察再转派 OpenCode。

通信原语：主 agent 可 spawn 高性能 worker、运行本 skill 自带脚本启动任意数量 OpenCode 进程；所有 worker 只通过仓库内 `.taboc/` 协调。OpenCode 进程不占 Codex/Claude subagent 槽，因此可与全部高性能槽同时工作。本 skill 独立安装、独立运行，不读取其他编排 skill 的文件或状态。

两条铁律：

1. **主 agent 不做业务任务。** 只拆单、路由、启动、维护黑板、轻量核实、上抛决策和汇总。
2. **便宜优先，按证据升级。** 任务只要未命中高风险门禁，就先交 OpenCode；失败或低置信度达到升级条件后才占高性能槽。
3. **消耗高级额度的子 agent 不得强于主 agent。** Codex/Claude 子 agent 最高只能与主 agent 持平；免费 OpenCode 不受此上限限制，但仍必须按任务复杂度选档，禁止因免费而无脑使用最强模型或最高 effort。

## 任务路由

先按风险选执行池，再按认知难度选 OpenCode 思考档位。不要按文件数量或“重要项目”笼统升级。

| 任务 | 默认执行池 | DeepSeek 档位 |
|---|---|---|
| 查文件、定位引用、整理日志、资料调研、竞品表、测试结果归纳 | OpenCode `readonly` | `medium`；跨模块调研用 `high` |
| 明确命令、单点改字、格式化、补小测试、机械重命名、低风险配置 | OpenCode `simple` | `medium` |
| 边界清楚的普通 bug、小功能、局部重构，已有定向测试 | OpenCode `simple` | `high` |
| 只读但链路复杂、根因不明、需综合大量证据 | OpenCode `readonly` | `max` |
| 认证/授权/支付/密码学的实现或设计裁决、生产数据写、不可逆操作、安全边界修改 | 高性能 agent | — |
| 跨系统架构语义、并发一致性、迁移兼容、需求含糊且错误代价高 | 高性能 agent | — |
| OpenCode 已按门禁失败或产出低置信度 | 高性能 agent 接替 | — |

超级简单任务允许 `medium`；不要为了“反正免费”一律 `max`。本机当前 DeepSeek V4 元数据支持 `low/medium/high/max`，不支持 `xhigh`。启动脚本每次按实时目录校验；未来出现新档位时可显式使用。

高性能 Codex/Claude 子 agent **默认继承主 agent 模型，禁止 model override**，只可以降低 effort；例如主 agent 是 `Luna-max`，子 agent 可用 `Luna-max/high/medium`，不得用任何 `Sol-*`。不能用“Sol 只开 high”抵消模型家族升级。免费 OpenCode 是明确例外：因为不消耗高级额度，可用比主 agent 更强的免费模型，也可开更高 effort，但仍严格使用上方复杂度路由表。免费模型同样有配额和延迟成本：超简单/机械任务优先 `medium`，普通低风险任务 `high`，只有复杂只读综合才用 `max`；禁止“反正免费就全开 max”。

只读任务不因领域名称自动升级：鉴权、支付、迁移等只读定位仍先用 OpenCode `readonly:max`，证据证明后续写入命中高风险门禁时再换执行池。不得把密钥、`.env`、生产数据、个人信息或未脱敏日志放进 prompt；调用 `/taboc` 视为允许 OpenCode 读取任务所需的普通仓库源码，不扩大到这些敏感内容。

### 省额度审计

每个高性能派单的 `[ROUTE]` 必须带 `gate=<命中的具体门禁>`；写不出 gate 就改派 OpenCode。混合批次若超过一半任务被派给高性能 agent，主 agent 必须在启动前逐项复核，优先拆出其中的只读侦察、测试编写、机械改动和局部实现交给 OpenCode。这个比例是防滑坡审计，不是把真正高风险任务硬塞给便宜模型。

### 强制升级条件

只有出现以下任一证据才从 OpenCode 升级：

- 写出 `[DECISION]`，涉及语义选择且无法从仓库事实消解；
- 定向测试连续两次未能由同一根因解释，或修复引入新失败；
- OpenCode 回报证据不足、改动超出边界、持锁异常或无法形成可信 `[HANDOFF]`；
- 侦察证明实际命中上表高风险门禁；
- 所有可用免费模型均因额度、服务或兼容性失败。

模型限量不等于任务太难：启动脚本会先换免费模型。切换模型仍失败，才由主 agent 决定是否升级。禁止高级 agent 预先复核所有 OpenCode 产出；定向测试与最终全量验证才是门禁。

## 黑板契约

```text
.taboc/
  locks/               # 每个被改文件一个原子锁目录
  board.md             # 小型任务队列，只放认领指针
  journal.md           # append-only 事件日志
  assignments.tsv      # task/agent/pool/model/effort 追加式登记
  sealed.log           # 收口成功记账
  opencode/            # 启动状态、pid、日志、prompt；不得提交
```

`board.md` 只放 `任务 / 认领者 / 执行池 / 状态`。根因、交接、决策、完成证据写 `journal.md`：

```markdown
[ROUTE] scout-auth | opencode | readonly | high | 查鉴权调用链
[ROUTE] impl-payment | premium | gate=支付边界写入 | 修改签名校验
[HANDOFF] scout-auth → impl-auth | 入口 api/auth.ts:42，校验在 guards.ts:88
[DONE] impl-auth | 修鉴权 | 根因 guards.ts:88 | 改 guards.ts,auth.test.ts | 定向测试红→绿 | 无遗留
[SEAL] /repo/web | sub | main | src/guards.ts,test/auth.test.ts | fix(web): 修复鉴权
[DECISION] impl-billing | 是否清理生产历史数据？
[MODEL_FALLBACK] scout-auth | opencode/deepseek-v4-flash-free:max → opencode/nemotron-3-ultra-free | quota
[POOL_BLOCKED] scout-auth | opencode/launchd unavailable | keep task queued; do not upgrade
[VERIFY] integration-verify | 全量测试 | PASS | npm test | 基线通过，无新增失败
```

- 实现任务释放锁后写 `[DONE]` + `[SEAL]`；纯只读任务写 `[HANDOFF]`。
- `[SEAL]` 必须单行且字段准确；脚本只读它，不从自由文本猜白名单。
- OpenCode 的 stdout 只是诊断，journal 才是完成权威。

### 原子文件锁

改文件 `F` 前：

```bash
L=.taboc/locks/$(printf '%s' "F" | sed 's#/#__#g')
mkdir "${L}" 2>/dev/null && { printf '%s %s\n' "<agent-id>" "F" > "${L}/meta"; echo GOT; } || echo BUSY
```

`GOT` 才改。`BUSY` 时拉其他 open 任务，禁止等锁空转。改完立即释放：

```bash
rm "${L}/meta" && rmdir "${L}"
```

## 主 agent 流程

1. 初始化 `.taboc/locks/`、`.taboc/opencode/`、board、journal；把 `.taboc/` 加 `.gitignore` 的修改派 worker。
2. 拆出真正可并行的一站式任务。默认不加 scout 跳；只有侦察结论供多个下游复用才 `scout → HANDOFF → impl`。
3. 用路由表分池，在 journal 写 `[ROUTE]`；高性能派单必须写 `gate=`。先填满所有可并行 OpenCode 任务，再用全部可用高性能 agent 槽承接高风险任务；**不得为等待 OpenCode 人为保留空槽**。
   每个高性能任务在 spawn 前必须登记实际模型和努力程度，不得写 `auto`/`unknown`。spawn 时不传 model override，让子 agent 继承主模型；登记脚本会拒绝不同模型或更高 effort：

   ```bash
   bash <skill-dir>/scripts/register-assignment.sh --repo "<绝对路径>" \
     --task "<task-id>" --agent "<agent-id>" --pool premium \
     --model "<与主 agent 相同的模型>" --effort "<不高于主 agent 的 effort>" \
     --main-model "<主 agent 模型>" --main-effort "<主 agent effort>"
   ```
4. 批量派单前先跑一次执行池预检；失败就记 `[POOL_BLOCKED]`、保留 OpenCode 队列并报告用户，**禁止把整批任务升级高级模型**：

   ```bash
   bash <skill-dir>/scripts/launch-opencode.sh --check
   ```

5. 为 OpenCode 写完整 prompt 文件，然后调用：

   ```bash
   bash <skill-dir>/scripts/launch-opencode.sh \
     --repo "<绝对路径>" --id "<agent-id>" --profile readonly \
     --effort high --prompt-file "<绝对 prompt 路径>"
   ```

   连续启动所有独立任务，每次必须检查 launch 命令退出码；首个环境级失败就停止继续启动。脚本使用 `launchctl bootstrap` 加载 `KeepAlive=false` 的一次性 LaunchAgent，worker 不属于 Codex 命令的进程组，但退出后不会被自动重启。启动时自动登记 `auto-free` 和请求档位，状态文件随后会覆盖为真实模型/档位。免费 OpenCode 不受主 agent 模型/effort 上限约束。
6. 高性能 worker 使用 harness 的 spawn 工具并嵌入同一黑板协议。不要传 model override，默认继承主 agent 模型；若 harness 不能继承或无法确认主模型，就不 spawn 该高性能子 agent。主 agent 不重复其工作。
7. 轮询用一条命令聚合，避免逐个读大日志：

   ```bash
   bash <skill-dir>/scripts/status-opencode.sh --repo "<绝对路径>"
   ```

   日常只读 `board.md`、journal 尾部和聚合状态；仅失败时打开对应日志。
   当用户说“**看看任务面板**”、“任务面板”或“谁在做什么”时，必须运行下面命令并原样展示表格；每任务都要有 `Model` 和 `Effort`：

   ```bash
   bash <skill-dir>/scripts/task-panel.sh --repo "<绝对路径>"
   ```
8. `[HANDOFF]` 放行 blocked 下游；`[DECISION]` 立即上抛用户；符合强制升级条件才派高性能接替者。
9. 全部实现有 `[DONE]+[SEAL]`、只读有 `[HANDOFF]`、锁全释放后，创建唯一高性能 git-ops 跑全量验证与收口。

## OpenCode prompt 协议

每个 prompt 文件必须完整包含以下内容并替换占位符。只读任务删除实现分支；实现任务不得删除锁、测试和完成门禁。

```text
【taboc 协议】
仓库：<绝对路径>；分支：<目标分支>；你的 id：<agent-id>；profile：<readonly|simple>。
黑板：<仓库>/.taboc/board.md、journal.md、locks/。只改工作区，绝不 commit/push。

任务：<用户口径原话>。
输入：<已知事实；HANDOFF 只写“自行读 journal 对应条目”>。
边界：<禁改文件、敏感信息、其他 worker 范围>。
验证：<定向命令与既有失败基线>；不得运行或声称通过全量测试。
输出预算：结论短写；证据用 file:line；不要复述大段源码或日志。

profile=readonly：不得编辑任何业务文件，不得写 [SEAL]；完成后 append：
  [HANDOFF] <你> → <下游或主 agent> | <结论与 file:line 证据>

profile=simple：改文件 F 前执行：
  L=.taboc/locks/$(printf '%s' "F" | sed 's#/#__#g')
  mkdir "${L}" 2>/dev/null && { printf '%s %s\n' "<agent-id>" "F" > "${L}/meta"; echo GOT; } || echo BUSY
GOT 才改；BUSY 拉其他 open 任务，禁止空转。先写复现测试红，再修绿，只跑定向测试。改完执行 `rm "${L}/meta" && rmdir "${L}"` 释放锁。
释放全部锁后 append 两行：
  [DONE] <你> | <任务> | 根因 file:line | 改动 | 定向测试红→绿 | 遗留
  [SEAL] <仓绝对路径> | <子模块或 -> | <分支> | <相对文件,逗号分隔> | <commit msg>

设计语义、数据写、生产写、高风险或不可逆动作不得自裁：append
  [DECISION] <你> | <问题与推荐选项>
然后停止。最终回复只给完成状态、证据和遗留。无 open 任务时结束，禁止 idle。
```

`readonly` 权限由脚本强制禁止 shell 和业务文件写入，仅允许内置只读工具及写 `.taboc/journal.md`。`simple` 允许工作区修改与测试，但脚本拒绝 commit、push、reset、clean、切分支、sudo 和递归删除。不要传 `--dangerously-skip-permissions`。

## 模型与失败策略

`opencode-worker.sh` 默认候选顺序：

1. `opencode/deepseek-v4-flash-free`，使用请求档位；
2. 其余实时可见的 OpenCode `*-free` 模型，按脚本内偏好顺序；
3. 用户通过 `TABOC_MODELS` 显式配置的其他模型。

只有 OpenCode JSONL 中顶层 `type=error` 的结构化错误事件（额度、429/402、容量、模型不可用、网络中断等）或 CLI 非零退出才自动换模型。禁止对整段日志搜索 `quota/capacity/402`：任务正文、源码和协议自身可能包含这些词。当次运行新写入的 `[HANDOFF]`/`[DONE]`/`[DECISION]` 是完成权威，即使 CLI 退出码异常也不得重做。正常退出却没有终态记录时标记 `incomplete`，只续跑一次，不自动换模型。重启已有终态记录的同 id 会被拒绝；确需人工重试时显式传 `--retry`。

失败重试前脚本只清理由同一 worker id 持有的锁，保留已有改动供下一模型检查并续做；因此 prompt 必须要求幂等地检查现状。

`TABOC_MODELS` 是逗号分隔候选列表；`TABOC_MAX_ATTEMPTS` 可限制尝试数。免费优先是硬默认：除非用户显式把付费模型写入 `TABOC_MODELS`，脚本不自行花钱。免费候选可以强于主 agent；这一例外不得扩展到消耗 Codex/Claude 额度的子 agent。

OpenCode 可执行文件按 `TABOC_OPENCODE_BIN` → 当前 PATH → `/opt/homebrew/bin/opencode` → `/usr/local/bin/opencode` → `~/.local/bin/opencode` 探测。找不到可执行文件、缺少 launchctl、launchd 提交失败都属于**执行池环境故障**，不是业务任务失败，也不是模型耗尽；必须写 `[POOL_BLOCKED]` 并暂停队列。

## 进度、异常与收口

进度只来自 `[HANDOFF]`、`[DONE]+[SEAL]`、`[DECISION]` 和状态文件；禁止编造平滑百分比。OpenCode `running` 但 journal 无新事件时写“运行中，无里程碑信号”。

| 情况 | 处置 |
|---|---|
| DeepSeek 限额/服务失败 | 脚本自动换免费模型并记 `[MODEL_FALLBACK]` |
| 所有免费模型真实调用失败 | 状态为 `exhausted`；逐任务按风险决定接替，禁止整批升级 |
| `opencode`/launchctl/launchd 环境故障 | 状态为 `blocked`；暂停便宜池、修环境或请用户处理，禁止升级这批任务 |
| OpenCode 进程失联且持锁 | 确认 pid 已死；只删 meta 所属 id 的锁，任务退回 open |
| 完工记录齐但进程状态未收尾 | 以 journal 推进；不得重复启动同 id |
| 任务文本出现 quota/capacity/402 | 不作为失败；只认顶层 `type=error` 事件 |
| worker 已退出 | 一次性 LaunchAgent 不重启；以 journal/status 确定终态 |
| 输出看似完成但记录不齐 | 补发一次续跑；仍不齐则高性能 agent 只做验收/接替，不重做侦察 |
| 两 worker 撞任务 | board 回读失败者让位；锁保证文件不被覆盖 |

收口顺序不可变：

1. 完成记录齐，锁全释放；
2. 唯一高性能 git-ops 在合并工作区跑本批次真实全量测试，写新的 `[VERIFY] PASS/FAIL`；
3. 仅新的 PASS 可执行：

   ```bash
   bash <skill-dir>/seal-from-journal.sh --dry-run
   bash <skill-dir>/seal-from-journal.sh
   ```

4. git-ops 只从 `[SEAL]` 取白名单，禁 force push；失败后重跑同一脚本，已成功项由 `sealed.log` 跳过。

## 收尾自检

- OpenCode 是否默认承接了所有未命中高风险门禁的任务，而非只接杂活？
- 超简单任务是否用了 `medium`，普通低风险用了 `high`，复杂只读才用了 `max`？
- 是否并行启动全部独立 OpenCode 任务，同时用满可用高性能槽？
- 是否没有让高性能 agent 预先重复侦察或普遍复核？
- OpenCode 批量派单前是否通过 `--check`，环境阻塞时是否保持队列而未整批升级？
- 每个任务是否登记了实际模型和努力程度，“看看任务面板”时能否逐项展示？
- 每个消耗高级额度的 Codex/Claude 子 agent 是否继承主模型且 effort 不高于主 agent？免费 OpenCode 是否没有被错误限档？
- 每个改文件是否锁定并释放，完成记录是否齐全？
- 本批次是否有新的全量 `[VERIFY] PASS`，git-ops 是否只按 `[SEAL]` 收口？
