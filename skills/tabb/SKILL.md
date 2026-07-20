---
name: tabb
description: 去中心化黑板多 agent 编排。仅由 /tabb 手动触发；用共享 board/journal 和原子文件锁协调多 agent 并行改同一仓库。
---

# tabb 黑板编排

## 边界与硬规则

tabb 仅在用户显式调用 `/tabb` 时生效。它的价值是多 agent 并行改同一仓时的文件级避让；本 skill 自带所有协议与脚本，不读取其他 skill。

1. 主 agent 只拆单、派单、门禁、用户交互和收口；业务读改、测试、git 都交给 worker。
2. 默认一个 worker 一站式查→改→验。只有根因不明且侦察结论供多个下游共用时，才拆 `scout → [HANDOFF] → impl`。
3. journal 是完成权威：实现需 `[DONE]+[SEAL]`，只读需 `[HANDOFF]`。worker 最终回复只是摘要，缺失不得导致重复派单。
4. 普通 worker 不 commit/push；唯一 git-ops 在新的全量验证 PASS 后统一收口。

## 模型与派发

| 类别 | 判定 | 运行档 |
|---|---|---|
| `readonly` | 需要理解、判断或综合结论的只读任务（默认） | 当前主模型 / `medium` |
| `readonly-low` | 明确为机械检索、事实收集，不需要推理取舍 | 当前主模型 / `low` |
| `work` | 实现、测试、修复、git-ops | 当前主模型 / 当前主 effort |

任务难度只决定拆单和跳数，不决定模型。每张单先跑脚本并原样登记：

```bash
python3 <skill-dir>/scripts/route-task.py --class <readonly|readonly-low|work> \
  --current-model "<当前主模型>" --current-effort "<当前主 effort>"
bash <skill-dir>/scripts/register-assignment.sh --repo "<仓库>" \
  --task "<task>" --agent "<agent>" --role "<readonly|implementation|git-ops>" \
  --model "<脚本 model>" --effort "<脚本 effort>"
```

- `work`：spawn 省略 `model` 和 `reasoning_effort`，继承当前主 agent。
- `readonly`：spawn 省略 `model`，传 `reasoning_effort="medium"`。只有任务卡能写出“机械检索/事实收集”的明确理由时才用 `readonly-low` 并传 `low`；Codex 中覆盖 effort 用 `fork_turns="none"` 或正整数。
- spawn 成功后才把 board 标为 `doing`；失败标 `blocked:<真实错误>`。禁止为 worker 改传其他模型。

## 黑板协议

```text
.tabb/
  board.md          # Task / Agent / State，只放状态指针
  journal.md        # append-only 事件
  assignments.tsv  # task/agent/role/model/effort
  locks/            # 文件级原子锁
  sealed.log        # 已收口记账

[HANDOFF] scout → impl | 结论与 file:line
[DONE] impl | 任务 | 根因 file:line | 改动 | 定向测试 | 遗留
[SEAL] /仓绝对路径 | 子模块或 - | 分支 | 相对文件,逗号分隔 | commit msg
[DECISION] agent | 问题与推荐选项
[BLOCKED] agent | 原因与所需条件
[VERIFY] git-ops | 全量测试 | PASS/FAIL | 命令 | 证据
```

改文件 `F` 前抢锁：

```bash
L=.tabb/locks/$(printf '%s' "F" | sed 's#/#__#g')
mkdir "${L}" 2>/dev/null && { printf '%s %s\n' "<agent-id>" "F" > "${L}/meta"; echo GOT; } || echo BUSY
```

`GOT` 才可修改，改完立即 `rm -rf "${L}"`。`BUSY` 时先做本任务内其他未锁工作；无事可做就写 `[BLOCKED]` 并返回，不得擅自认领其他类别任务或复制错误路由。

## 主 agent 流程

1. 初始化 `.tabb/locks/`、board、journal、assignments；在第一个写入任务中将 `.tabb/` 加入 `.gitignore`。
2. 拆成文件边界尽量独立的任务；有依赖的单先标 `blocked`。
3. 路由、登记、spawn；每个 worker 都必须收到下节的完整协议。
4. 读 board/journal/locks 推进；`[DECISION]` 立即上抛，`[HANDOFF]` 放行对应下游。
5. 终态齐且锁全释放后关闭 worker，再派唯一 git-ops 全量验证和收口。
6. 只从真实 journal、测试、git 和远端回执汇报。

## Worker 派单协议

每张派单必须包含：

```text
【tabb 协议】
仓库/分支/id：<绝对路径> / <分支> / <agent-id>
调度：class=<readonly|readonly-low|work>；model=<脚本 model>；effort=<脚本 effort>；role=<readonly|implementation|git-ops>
任务：<用户口径>；输入：<已知结论>；边界：<禁改/其他 agent 范围>；验证：<定向命令与基线>
普通 worker 只改工作区，不 commit/push；git-ops 只按收口节执行。派单必须粘贴上节完整 mkdir 抢锁命令，不得只写“按协议”；释放全部锁后写终态。
实现：先复现后修复，只跑定向测试，写 [DONE]+[SEAL]。只读：禁止业务写入，只写 [HANDOFF]。
设计语义、数据写、生产写或不可逆动作：写 [DECISION] 后停止。最终回复摘要证据与遗留；journal 才是完成权威。
```

## 状态、异常与收口

用户问进度或任务面板时运行：

```bash
bash <skill-dir>/scripts/task-panel.sh --repo "<仓库>"
```

不编造百分比。出现锁超时、worker 失联、终态缺失或收口失败时，读 [references/failures.md](references/failures.md)；正常批次不加载。

收口顺序：终态齐→锁清空→本批次新 `[VERIFY] PASS`→预检→正式 seal。FAIL、缺 PASS 或复用旧 PASS 都禁止 commit/push。

```bash
bash <skill-dir>/seal-from-journal.sh --dry-run
bash <skill-dir>/seal-from-journal.sh
```

`seal-from-journal.sh` 只从 `[SEAL]` 生成白名单，并调用本 skill 自带的 `seal.sh`；禁止 force push。汇报时分开“已推送”与“已部署/构建/上传”。

## 收尾自检

- 未读取或引用其他 skill；主 agent 未做业务或 git 工作。
- 派发均继承当前模型；只读默认 medium，机械检索/事实收集才 low，写入任务同主 effort。
- 所有改文件都持锁；终态齐；无残留锁。
- 本批次全量验证 PASS；收口只用 `[SEAL]` 白名单。
