---
name: taboc
description: 异构模型的去中心化黑板多 agent 编排。仅由 /taboc 手动触发；只读优先交给 OpenCode DeepSeek，其他任务按固定路由交给 premium worker。
---

# taboc 异构黑板编排

## 边界与硬规则

taboc 仅在用户显式调用 `/taboc` 时生效。本 skill 自带黑板、OpenCode 启动、额度、面板与收口脚本，不读取其他 skill。OpenCode 池需 macOS `launchctl`、Python 3 和 `opencode` CLI；缺任一项就阻塞该池，不升级任务。

1. 主 agent 只拆单、路由、派单、门禁、用户交互和收口；不做业务读改、测试或 git。
2. OpenCode **只执行纯只读任务**；业务写入全部交给 premium worker。
3. 路由只认下表五档，必须跑脚本，不临场改模型/effort。
4. DeepSeek 限额即写全局 quota state，整个免费池停用；只读改路由 Luna-low，不试其他免费模型。
5. journal 是完成权威：实现需 `[DONE]+[SEAL]`，只读需 `[HANDOFF]`。唯一 git-ops 在新的全量验证 PASS 后收口。

## 固定路由

| 类别 | 判定 | 路由 |
|---|---|---|
| `readonly` | 零业务写入 | DeepSeek V4 Flash Free `medium`；额度期 Luna `low` |
| `simple` | 方案明确、修改机械、低风险 | Luna `medium` |
| `complex-short` | 有明显推理/取舍，但边界和验证清楚 | Luna `max` |
| `complex-long` | 紧耦合跨模块因果、深度多方案取舍或无法安全拆分 | Sol `medium` |
| `very-complex` | 跨系统架构、根因高度不明、安全/一致性关键或错误代价极高 | Sol `high` |

先拆成独立一站式任务，再逐张分类。文件多、耗时长、测试慢只是拆单信号，不是 Sol 证据；选 Sol 必须在 `[ROUTE]` 写出无法靠继续拆单消除的推理难点。没有具体复杂证据时按较低档。

```bash
python3 <skill-dir>/scripts/route-task.py --class <readonly|simple|complex-short|complex-long|very-complex>
```

## 黑板与终态

初始化 `.taboc/locks/`、`.taboc/opencode/`、board、journal、assignments。有写入任务时，在首个写入边界中将 `.taboc/` 加入 `.gitignore`；纯只读批次不改仓库。board 只放 `Task / Agent / Pool / State`；详情只进 journal：

```text
[ROUTE] task | class | model | effort | 判定理由
[HANDOFF] scout → impl | 结论与 file:line
[DONE] impl | 任务 | 根因 file:line | 改动 | 定向测试 | 遗留
[SEAL] /仓绝对路径 | 子模块或 - | 分支 | 相对文件,逗号分隔 | commit msg
[DECISION] agent | 问题与推荐选项
[VERIFY] git-ops | 全量测试 | PASS/FAIL | 命令 | 证据
```

## 派发

### OpenCode 只读

1. 路由输出 OpenCode 时先预检：`bash <skill-dir>/scripts/launch-opencode.sh --check`。
2. 用自带生成器写完整只读 prompt：

   ```bash
   python3 <skill-dir>/scripts/write-worker-prompt.py \
     --output "<仓库>/.taboc/opencode/<id>.prompt" --repo "<仓库>" --branch "<分支>" \
     --id "<id>" --task "<任务>" --context "<已知事实>" \
     --boundary "<禁读和敏感边界>" --validation "<定向检查>"
   bash <skill-dir>/scripts/launch-opencode.sh --repo "<仓库>" --id "<id>" \
     --effort medium --prompt-file "<绝对 prompt 路径>"
   ```

OpenCode 任务连续启动，运行并行。额度错误对原任务重跑路由；其他池故障阻塞并报告，不试其他免费模型。

### Premium worker

spawn 前登记路由脚本的精确 model/effort：

```bash
bash <skill-dir>/scripts/register-assignment.sh --repo "<仓库>" \
  --task "<task>" --agent "<agent>" --pool premium \
  --model "<脚本 model>" --effort "<脚本 effort>"
```

目标模型在 spawn allowlist 时显式传 model/effort；目标模型等于当前主模型但不在 allowlist 时，省略 `model` 继承，仍精确传 effort。其他情况在 spawn 前阻塞；禁止换模型。spawn 成功后才标 `doing`。

每个普通 premium prompt 必须自带以下协议：git-ops 只按收口节执行：

```text
【taboc premium 协议】
仓库/分支/id：<绝对路径> / <分支> / <agent-id>
任务：<用户口径>；输入：<已知结论>；边界：<禁改范围>；验证：<定向命令与基线>
只改工作区，不 commit/push；先复现后修复，只跑定向测试。
改文件 F 前执行：`L=.taboc/locks/$(printf '%s' "F" | sed 's#/#__#g'); mkdir "${L}" 2>/dev/null && { printf '%s %s\n' "<agent-id>" "F" > "${L}/meta"; echo GOT; } || echo BUSY`。GOT 才改，改完立即 `rm -rf "${L}"`。
释放全部锁后写 [DONE]+[SEAL]。设计语义、数据写、生产写或不可逆动作写 [DECISION] 后停止。
```

## 状态、异常与收口

日常只跑聚合状态，失败时才读单 worker 日志：

```bash
bash <skill-dir>/scripts/status-opencode.sh --repo "<仓库>"
bash <skill-dir>/scripts/task-panel.sh --repo "<仓库>"
```

进度只来自 journal 和状态文件，不编百分比。出现 `blocked/exhausted/incomplete/lost/failed`、额度、SQLite 锁、终态缺失或收口失败时，读 [references/failures.md](references/failures.md)；正常批次不加载。

收口顺序：终态齐→锁清空→关闭 worker→唯一 git-ops 产生本批次新 `[VERIFY] PASS`→预检→正式 seal。

```bash
bash <skill-dir>/seal-from-journal.sh --dry-run
bash <skill-dir>/seal-from-journal.sh
```

FAIL、缺 PASS 或复用旧 PASS 都禁止 commit/push。收口只从 `[SEAL]` 取白名单，禁止 force push。最终核对：路由与登记一致；额度期零 OpenCode 调用；终态、锁、新 PASS、白名单与远端 SHA 均真实。
