---
name: taboc
description: 异构模型的去中心化黑板多 agent 编排。仅由 /taboc 手动触发。需要保持或扩大并发，同时把只读、调研、机械性和低风险实现优先交给本机 OpenCode 免费模型，把高风险或高难度任务留给 Codex/Claude 时使用；内置模型与思考档位降级、权限隔离、失败升级和统一收口。
---

# taboc 异构黑板编排

## 核心规则

通过仓库内 `.taboc/` 黑板协调两类执行池。OpenCode worker 不占 Codex/Claude subagent 槽，可和全部 premium 槽并发。本 skill 独立安装，不读取其他编排 skill。

1. **主 agent 不做业务任务**：只拆单、路由、派单、维护黑板、上抛决策、门禁和汇总。
2. **OpenCode 是默认执行池**：未命中高风险门禁就先交免费模型，不让 premium 预先侦察或普遍复核。
3. **按证据升级**：模型限量先换免费模型；任务风险或失败证据达到门禁才升级。
4. **premium 子 agent 不得强于主 agent**：可继承主模型或使用同系列已知弱档，effort 只能持平或降低；已知顺序为 `Sol > Luna > Terra`、`Opus > Sonnet > Haiku`，未知或跨系列只允许同模型。免费 OpenCode 不受此模型上限限制，但禁止因为免费而全开 max。

## 路由

先按风险选池，再按认知难度选 OpenCode effort：超级简单 `medium`，普通低风险 `high`，复杂只读综合 `max`。

| 任务 | 池 | effort |
|---|---|---|
| 查文件、引用、日志、资料；机械改字、格式化、小测试、明确配置 | OpenCode `readonly`/`simple` | `medium` |
| 跨模块调研；边界清楚的普通 bug、小功能、局部重构 | OpenCode `readonly`/`simple` | `high` |
| 根因不明、需综合大量证据的只读任务 | OpenCode `readonly` | `max` |
| 认证/授权/支付/密码学写入，生产数据写，不可逆操作，安全边界修改 | premium | — |
| 跨系统架构语义、并发一致性、迁移兼容、需求含糊且错误代价高 | premium | — |

只读任务不因领域名称自动升级；鉴权、支付、迁移的只读定位仍先用 `readonly:max`。不得把密钥、`.env`、生产数据、个人信息或未脱敏日志放入 prompt。

每个 premium `[ROUTE]` 必须带 `gate=<命中的具体门禁>`；写不出 gate 就改派 OpenCode。若混合批次过半任务进入 premium，启动前逐项复核并拆出只读、测试、机械改动和局部实现。

只有以下证据允许升级：

- `[DECISION]` 涉及无法从仓库事实消解的语义选择；
- 定向测试连续两次无法由同一根因解释，或修复引入新失败；
- OpenCode 证据不足、越界、持锁异常或无法形成可信终态；
- 侦察证明命中高风险门禁；
- 所有可用免费模型真实调用失败。

## 黑板

初始化 `.taboc/locks/`、`.taboc/opencode/`、`board.md`、`journal.md`、`assignments.tsv`；把 `.taboc/` 加 `.gitignore` 的任务派 worker。`board.md` 只放 `任务/认领者/执行池/状态`，详情追加到 journal：

```text
[ROUTE] scout-auth | opencode | readonly | high | 查鉴权链路
[ROUTE] impl-payment | premium | gate=支付边界写入 | 修改签名校验
[HANDOFF] scout-auth → impl-auth | 结论与 file:line
[DONE] impl-auth | 任务 | 根因 file:line | 改动 | 定向测试红→绿 | 遗留
[SEAL] /repo/web | sub | main | src/a.ts,test/a.test.ts | fix(web): message
[DECISION] impl-billing | 问题与推荐选项
[VERIFY] integration-verify | 全量测试 | PASS | command | 证据
```

实现任务必须 `[DONE]+[SEAL]`；只读任务必须 `[HANDOFF]`。stdout 仅供诊断，journal 是完成权威。

## 派单流程

1. 拆成真正独立的一站式任务。只有一个侦察结论供多个下游复用时才拆 `scout → HANDOFF → impl`。
2. 写 `[ROUTE]`，先填满全部 OpenCode 任务，再用满可用 premium 槽；不得为等待 OpenCode 留空槽，也不得双做同一任务。
3. 批量启动 OpenCode 前预检；失败写 `[POOL_BLOCKED]`、保留队列并报告，禁止整批升级：

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

5. 连续启动全部独立 OpenCode 任务；每次检查退出码，首个环境级失败便停止继续启动。launcher 使用一次性 LaunchAgent，短暂错峰模型查询和 CLI 冷启动，任务执行仍并行。超时按 profile/effort 分级；有日志活动便续期，另设总时长上限：

   ```bash
   bash <skill-dir>/scripts/launch-opencode.sh --repo "<仓库>" --id "<id>" \
     --profile readonly --effort high --prompt-file "<绝对 prompt 路径>"
   ```

6. premium worker 按任务难度选择主模型或同系列弱档；使用弱档时传 harness 支持的 override，继承时不传 model override。spawn 前登记实际值；脚本拒绝强档、无法证明的跨系列或更高 effort：

   ```bash
   bash <skill-dir>/scripts/register-assignment.sh --repo "<仓库>" \
     --task "<task>" --agent "<agent>" --pool premium \
     --model "<主模型或同系列弱档>" --effort "<不高于主 effort>" \
     --main-model "<主模型>" --main-effort "<主 effort>"
   ```

7. 主 agent 不重复 worker 工作。日常用一条聚合命令轮询，只在失败时读对应日志：

   ```bash
   bash <skill-dir>/scripts/status-opencode.sh --repo "<仓库>"
   ```

8. `[HANDOFF]` 放行下游；`[DECISION]` 立即上抛；只按升级门禁接替失败任务。

## 任务面板

用户说“看看任务面板”“任务面板”或“谁在做什么”时，必须运行并原样展示；每项都要显示实际 `Model` 和 `Effort`：

```bash
bash <skill-dir>/scripts/task-panel.sh --repo "<仓库>"
```

进度只来自 journal 和状态文件，不编百分比。`running` 且无 journal 新事件时只说“运行中，无里程碑信号”。

## 异常与收口

出现 `blocked/exhausted/incomplete/lost/failed`、SQLite 锁、终态缺失或收口失败时，先读 [references/failures.md](references/failures.md)，按对应条目处理；正常批次不要加载。

所有实现终态齐、只读交接齐、锁全释放后，创建唯一 premium git-ops：

1. 在合并工作区跑本批次真实全量测试，写新的 `[VERIFY] PASS/FAIL`；
2. 仅新 PASS 可运行 `seal-from-journal.sh --dry-run`，再正式运行；
3. 只从 `[SEAL]` 取白名单，禁止 force push。

收尾只核对四件事：OpenCode 是否承接所有非高风险任务；effort 是否按 `medium/high/max` 分级；premium model/effort 是否均未超过主 agent；终态、锁、全量 PASS 和收口白名单是否齐全。
