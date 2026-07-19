# taboc 异常手册

仅在预检失败、worker 非正常终态、状态失联或收口失败时读取本文件。正常批次不要加载。

## 模型与 OpenCode 运行时

| 情况 | 处置 |
|---|---|
| DeepSeek 限额、服务错误、单次超时 | worker 自动切换下一免费模型并记 `[MODEL_FALLBACK]`；不要升级任务难度 |
| 实时模型目录为空或失败 | worker 使用内置已知免费候选继续真实调用；不得把 `tried=0` 当模型耗尽 |
| 所有候选真实调用失败 | 状态 `exhausted`；逐任务按风险决定接替，禁止整批升级 |
| `opencode`、launchctl、launchd 故障 | 写 `[POOL_BLOCKED]`，保留队列并修环境或报告用户；禁止升级这批任务 |
| 正常退出但没有终态 | 状态 `incomplete`；同模型仅续跑一次，仍失败再验收或接替 |
| 最终 JSON 含严格匹配 worker id 的终态 | worker 自动补写 journal；不匹配的自由文本不采纳 |
| 任务正文出现 quota、capacity、402 | 不算错误；只认顶层 `type=error` 或 CLI 非零退出 |

每个模型默认 300 秒超时。需要调整时设置 `TABOC_ATTEMPT_TIMEOUT`；`TABOC_MODELS` 指定逗号分隔候选；`TABOC_MAX_ATTEMPTS` 限制次数；`TABOC_STARTUP_HOLD` 调整冷启动错峰。launcher 会透传这些变量。除非用户显式把付费模型写入 `TABOC_MODELS`，worker 不自行花钱。

## 并发、状态与锁

- 模型查询和 CLI 冷启动短暂串行化以避开 OpenCode SQLite 锁；模型执行仍并行，不要手工改成逐个等待。
- 面板标 `lost`：以 run lock + pid 双重确认；只清理 `meta` 所属 id 的锁，把任务退回 open。
- journal 已有终态但进程状态未收尾：以 journal 推进，不重复启动同 id。
- 两 worker 撞任务：board 回读失败者让位；文件锁决定写权限。
- 失败重试只清同一 worker id 的锁，保留已有改动；续跑 prompt 必须要求先检查现状。

## 收口故障

只允许唯一 premium git-ops 收口。先确认 `[DONE]+[SEAL]` 或 `[HANDOFF]` 齐全、锁清空，再跑全量测试并写本批次新的 `[VERIFY] PASS/FAIL`。仅新 PASS 可运行：

```bash
bash <skill-dir>/seal-from-journal.sh --dry-run
bash <skill-dir>/seal-from-journal.sh
```

脚本仅从 `[SEAL]` 取白名单，禁止 force push。失败后重跑同一脚本；`sealed.log` 会跳过已成功项。
