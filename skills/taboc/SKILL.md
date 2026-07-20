---
name: taboc
description: 异构模型的去中心化黑板多 agent 编排。仅由 /taboc 手动触发。按固定五档把只读任务优先交给 OpenCode DeepSeek 免费模型，其余任务精确路由到 Luna/Sol，并提供共享额度熔断、权限隔离和统一收口。
---

# taboc 异构黑板编排

## 核心规则

通过仓库内 `.taboc/` 黑板协调两类执行池。OpenCode worker 不占 Codex/Claude subagent 槽，可和全部 premium 槽并发。本 skill 独立安装，不读取其他编排 skill。

1. **主 agent 不做业务任务**：只拆单、路由、派单、维护黑板、上抛决策、门禁和汇总。
2. **路由只认固定五档**：不参考主 agent 档位，不临场升降；必须运行路由脚本并照输出派发。
3. **共享额度熔断**：DeepSeek V4 限额即记录全局解除时间并停用整个 OpenCode 池；只读任务改派 Luna-low，不试其他免费模型。

## 路由

| 类别 | 判定 | 固定路由 |
|---|---|---|
| `readonly` | 零业务写入，只查代码、日志、资料、调用链 | DeepSeek V4 Flash Free `medium`；额度期 `gpt-5.6-luna / low` |
| `simple` | 方案明确、修改机械、低风险；规模大仍可属此档 | `gpt-5.6-luna / medium` |
| `complex-short` | 需要明显推理或取舍，但问题边界与验证路径清楚 | `gpt-5.6-luna / max` |
| `complex-long` | 推理本身复杂，且存在紧耦合跨模块因果、多方案深度取舍，或无法安全拆分的长链路 | `gpt-5.6-sol / medium` |
| `very-complex` | 跨系统架构、根因高度不明、安全/一致性关键或错误代价极高 | `gpt-5.6-sol / high` |

### 分类顺序与升档门禁

1. **先拆单，后分类。** 先把用户总需求拆成能独立实现、验证的一站式任务卡，再分别判档；禁止按原始总需求的体量给每张卡升档。
2. **规模只决定拆单，不决定模型。** 文件多、步骤多、预计耗时长、测试慢，都不是 `complex-long` 证据。大但清晰的任务应拆成多个 `simple` 一站式小单。
3. **Sol 必须有具体理由。** 选 `complex-long` / `very-complex` 时，`[ROUTE]` 理由必须写明哪个推理难点不能通过继续拆单消除；只能写出“文件多/耗时长/需一站式”时不得上 Sol。
4. **无复杂证据不上调。** 相邻档拿不准时，若没有上述具体复杂信号，按较低档；不得因“一站式”默认预留能力。

例：同一字段机械同步到 8 个页面并补测试，拆成几张 `simple`；需同时重构状态机、保持兼容性并在多种竞态方案间取舍，才可判 `complex-long`。不得自创第六档或改档。只读不因鉴权、支付、迁移等领域名升级；不得把密钥、`.env`、生产数据、个人信息或未脱敏日志放入 prompt。

## 黑板

初始化 `.taboc/locks/`、`.taboc/opencode/`、`board.md`、`journal.md`、`assignments.tsv`；把 `.taboc/` 加 `.gitignore` 的任务派 worker。`board.md` 只放 `任务/认领者/执行池/状态`，详情追加到 journal：

```text
[ROUTE] scout-auth | readonly | opencode/deepseek-v4-flash-free | medium | 查鉴权链路
[ROUTE] impl-payment | very-complex | gpt-5.6-sol | high | 修改签名校验
[HANDOFF] scout-auth → impl-auth | 结论与 file:line
[DONE] impl-auth | 任务 | 根因 file:line | 改动 | 定向测试红→绿 | 遗留
[SEAL] /repo/web | sub | main | src/a.ts,test/a.test.ts | fix(web): message
[DECISION] impl-billing | 问题与推荐选项
[VERIFY] integration-verify | 全量测试 | PASS | command | 证据
```

实现任务必须 `[DONE]+[SEAL]`；只读任务必须 `[HANDOFF]`。stdout 仅供诊断，journal 是完成权威。

## 派单流程

1. 拆成真正独立的一站式任务。只有一个侦察结论供多个下游复用时才拆 `scout → HANDOFF → impl`。
2. 每项先运行固定路由脚本，输出 `pool<TAB>model<TAB>effort`；原样写 `[ROUTE]` 并登记目标档，禁止手调。未成功 spawn 的 premium 任务保持 `open` / `blocked`，不得先标 `doing`：

   ```bash
   python3 <skill-dir>/scripts/route-task.py --class <readonly|simple|complex-short|complex-long|very-complex>
   ```

3. `readonly` 输出 OpenCode 时先预检；额度期脚本会直接输出 Luna-low。若调用中才触发 `[POOL_QUOTA]`，立即对原任务重跑路由并改派 Luna-low：

   ```bash
   bash <skill-dir>/scripts/launch-opencode.sh --check
   ```

4. 用生成器创建完整 worker prompt，不要自行重写锁和终态协议：

   ```bash
   python3 <skill-dir>/scripts/write-worker-prompt.py \
     --output "<仓库>/.taboc/opencode/<id>.prompt" --repo "<仓库绝对路径>" \
     --branch "<分支>" --id "<id>" --profile readonly \
     --task "<用户口径原话>" --context "<已知事实>" \
     --boundary "<禁改和敏感边界>" --validation "<定向命令>"
   ```

5. 连续启动所有 `readonly` OpenCode 任务；只调用 DeepSeek V4-medium。额度错误记录解除时间并转 Luna-low；其他模型故障停止并报告，不试其他免费模型。launcher 使用一次性 LaunchAgent，任务执行仍并行：

   ```bash
   bash <skill-dir>/scripts/launch-opencode.sh --repo "<仓库>" --id "<id>" \
     --profile readonly --effort medium --prompt-file "<绝对 prompt 路径>"
   ```

6. premium worker 在 spawn 前登记路由脚本给出的精确目标值，不得替换或手写 assignments 绕过脚本。spawn 参数按下节选显式覆盖或父模型继承：

   ```bash
   bash <skill-dir>/scripts/register-assignment.sh --repo "<仓库>" \
     --task "<task>" --agent "<agent>" --pool premium \
     --model "<脚本 model>" --effort "<脚本 effort>"
   ```

   spawn 成功后才把 board 改为 `doing`；失败则改为 `blocked:<真实错误>`，禁止面板虚报在途。

7. 主 agent 不重复 worker 工作。日常用一条聚合命令轮询，只在失败时读对应日志：

   ```bash
   bash <skill-dir>/scripts/status-opencode.sh --repo "<仓库>"
   ```

8. `[HANDOFF]` 放行下游；`[DECISION]` 立即上抛；失败接替仍按原任务类别重跑固定路由。

## Premium spawn 模型传递

路由脚本给出的 model/effort 是**目标实际运行档**；spawn 参数只是把它传给调度器的方式。派发前先读当前 spawn 工具声明的可显式覆盖模型，不用一次必然失败的调用做探测。

- **显式覆盖：**目标模型在工具 allowlist 中，显式传脚本给出的 `model` 和 `reasoning_effort`。
- **父模型继承：**目标模型不在 allowlist，但确认它就是当前主 agent 模型时，spawn **省略 `model`** 以继承当前模型；若工具允许独立覆盖 effort，仍传脚本的 `reasoning_effort`。Codex 中传 effort 时用 `fork_turns="none"` 或正整数，不用会强制全量继承 effort 的 `all`。
- **不可用：**目标模型既不能显式覆盖，也不是当前主模型（或目标 effort 也无法精确传递）时，在 spawn 前阻塞并如实报告。禁止改传 Sol/Terra 或其他模型。

父模型继承是同一目标模型的合法传递，不是静默替换。assignments 仍登记脚本的目标 model/effort；给用户的派单回执注明 `explicit` 或 `inherit-parent`，不把 UI 可选列表误当成 spawn allowlist。

## 任务面板

用户说“看看任务面板”“任务面板”或“谁在做什么”时，必须运行并原样展示；每项都要显示固定路由的精确模型与 effort，额度熔断时面板顶部显示解除时间：

```bash
bash <skill-dir>/scripts/task-panel.sh --repo "<仓库>"
```

进度只来自 journal 和状态文件，不编百分比。`running` 且无 journal 新事件时只说“运行中，无里程碑信号”。

## 异常与收口

出现 `blocked/exhausted/incomplete/lost/failed`、`[POOL_QUOTA]`、SQLite 锁、终态缺失或收口失败时，先读 [references/failures.md](references/failures.md)，按对应条目处理；正常批次不要加载。

所有实现终态齐、只读交接齐、锁全释放后，创建唯一 premium git-ops：

1. 在合并工作区跑本批次真实全量测试，写新的 `[VERIFY] PASS/FAIL`；
2. 仅新 PASS 可运行 `seal-from-journal.sh --dry-run`，再正式运行；
3. 只从 `[SEAL]` 取白名单，禁止 force push。

收尾只核对三件事：每项类别与固定路由是否一致；额度期只读是否 Luna-low 且零 OpenCode 调用；终态、锁、全量 PASS 和收口白名单是否齐全。
