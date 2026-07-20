# tabb 异常手册

仅在出现阻塞、失联、终态缺失或收口失败时读取。

| 情况 | 处置 |
|---|---|
| `BUSY` | 先做本任务其他未锁工作；无事可做写 `[BLOCKED]` 并返回，不擅自认领其他类别任务 |
| 超龄锁 | 用 `find .tabb/locks -maxdepth 1 -mindepth 1 -type d -mmin +10` 找候选；确认 meta 持有者已终止后才删锁、任务退回 open |
| worker idle/失联 | journal 终态齐则视为完成；终态不齐、仍持锁或测试未完成才派接替 |
| `[DECISION]` | 立即带推荐选项上抛用户，裁决追加到 journal |
| 面板 `unregistered` | 先补登记，不猜 model/effort |
| 全量验证 FAIL | 禁止 seal；派修复 worker，再产生新 `[VERIFY]` |
| seal 失败 | 修正真实问题后重跑同一脚本；`sealed.log` 会跳过已成功项 |
| push 瞬时失败 | 本地 commit 存在时只重试 push；持续失败时如实报告 |

用户称修复未生效时，先比对源码与构建产物内容/哈希，再查运行时链路。
