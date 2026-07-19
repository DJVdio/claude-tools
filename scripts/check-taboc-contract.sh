#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
ok() { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; FAIL=1; }

echo "══ taboc 独立性 ══"
if rg -n '\.tabb|skills/(ta|tabb)/|~/.+(ta|tabb)' skills/taboc; then
  bad "taboc 仍引用其他编排 skill 的路径或状态"
else
  ok "taboc 不读取其他编排 skill"
fi

for FILE in skills/taboc/seal.sh skills/taboc/seal-from-journal.sh skills/taboc/scripts/opencode-worker.sh skills/taboc/scripts/launch-opencode.sh skills/taboc/scripts/status-opencode.sh skills/taboc/scripts/register-assignment.sh skills/taboc/scripts/task-panel.sh skills/taboc/scripts/cap-effort.sh; do
  if [ -f "${FILE}" ]; then
    bash -n "${FILE}" && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
  else
    bad "缺少 ${FILE}"
  fi
done

echo "══ taboc 路由与权限门禁 ══"
rg -q 'OpenCode 是默认执行池' skills/taboc/SKILL.md && ok "便宜模型默认优先" || bad "缺少便宜模型默认路由"
rg -q 'gate=<命中的具体门禁>' skills/taboc/SKILL.md && ok "高级模型派单需具体门禁" || bad "缺少额度防滑坡审计"
rg -q 'medium.*high.*max' skills/taboc/SKILL.md && ok "思考档位分级存在" || bad "缺少思考档位分级"
rg -q 'TABOC_MODELS' skills/taboc/scripts/opencode-worker.sh && ok "支持模型候选覆盖" || bad "缺少模型候选覆盖"
rg -q 'rm -rf \*.*deny' skills/taboc/scripts/opencode-worker.sh && ok "实现 worker 禁递归删除" || bad "缺少递归删除门禁"
rg -q 'launchctl bootstrap' skills/taboc/scripts/launch-opencode.sh && ok "worker 由 launchd 托管" || bad "缺少脱离工具进程组的启动机制"
rg -q '"KeepAlive": False' skills/taboc/scripts/write-launch-plist.py && ok "launchd worker 为一次性任务" || bad "worker 可能被 launchd 无限重启"
rg -q '/opt/homebrew/bin/opencode' skills/taboc/scripts/launch-opencode.sh && ok "主动探测 Homebrew OpenCode" || bad "仍只依赖 PATH"
rg -q '\[POOL_BLOCKED\].*do not upgrade' skills/taboc/scripts/launch-opencode.sh && ok "环境故障禁止批量升级" || bad "缺少执行池阻塞门禁"
rg -q 'event.get\("type"\) == "error"' skills/taboc/scripts/classify-opencode-log.py && ok "只解析结构化错误事件" || bad "可能把任务文本误判为限额"
rg -q 'Task \| Agent \| Pool \| Model \| Effort \| State' skills/taboc/scripts/task-panel.py && ok "任务面板显示模型与努力程度" || bad "任务面板缺少调度详情"
rg -q 'check-model-ceiling.py' skills/taboc/scripts/register-assignment.sh && ok "高性能子 agent 模型受主模型上限约束" || bad "可能出现 Luna 主 agent 派 Sol 子 agent"
rg -q 'Sol > Luna > Terra' skills/taboc/SKILL.md && ok "premium 允许同系列已知弱档" || bad "低风险 premium 不能降模型省额度"
rg -q '免费 OpenCode 不受此.*限制' skills/taboc/SKILL.md && ok "免费模型不受主 agent 上限误伤" || bad "免费 OpenCode 被错误限制"
rg -q '禁止.*免费.*全开 max' skills/taboc/SKILL.md && ok "免费模型仍按复杂度选档" || bad "免费模型可能无脑使用最高档"
rg -q '省略该维.*reasoning_effort.*thinking.*override' skills/taboc/SKILL.md && ok "premium 同 effort 强制继承" || bad "premium 可能显式升级 effort"
rg -q '手写 assignments 绕过脚本' skills/taboc/SKILL.md && ok "premium 禁止伪造登记" || bad "premium 可绕过登记门禁"
if rg -q 'run-with-timeout.py' skills/taboc/scripts/opencode-worker.sh \
  && rg -q -- '--idle-timeout' skills/taboc/scripts/opencode-worker.sh \
  && rg -q -- '--hard-timeout' skills/taboc/scripts/opencode-worker.sh; then
  ok "单模型调用有活动感知超时与总时长上限"
else
  bad "模型可能误杀活跃任务或无限卡住 worker"
fi
rg -q 'startup.lock' skills/taboc/scripts/opencode-worker.sh && ok "OpenCode 冷启动有并发保护" || bad "并发冷启动可能争用 SQLite"
rg -q 'model-query.lock' skills/taboc/scripts/opencode-worker.sh && ok "模型目录查询有并发保护" || bad "并发模型查询可能争用 SQLite"
rg -q 'readonly:high.*450' skills/taboc/scripts/opencode-worker.sh \
  && rg -q 'simple:high.*600' skills/taboc/scripts/opencode-worker.sh \
  && ok "超时默认值按任务复杂度分级" || bad "所有任务可能再次共用固定超时"
rg -q 'extract-terminal-record.py' skills/taboc/scripts/opencode-worker.sh && ok "最终 JSON 终态可安全恢复" || bad "模型完成但 journal 可能缺终态"
rg -q 'TABOC_ATTEMPT_TIMEOUT TABOC_ATTEMPT_HARD_TIMEOUT TABOC_STARTUP_HOLD' skills/taboc/scripts/launch-opencode.sh && ok "LaunchAgent 透传运行策略" || bad "launcher 丢失模型或超时配置"
rg -q 'run_lock.exists' skills/taboc/scripts/task-panel.py && ok "任务面板校验 worker 活性" || bad "任务面板可能永久显示陈旧 running"
rg -q 'write-worker-prompt.py' skills/taboc/SKILL.md && ok "完整 worker 协议由脚本生成" || bad "主 agent 可能现编 worker 协议"
rg -q '仅在.*非正常终态' skills/taboc/references/failures.md && ok "异常手册按需加载" || bad "异常细则可能常驻上下文"

for FILE in skills/taboc/scripts/classify-opencode-log.py skills/taboc/scripts/task-panel.py skills/taboc/scripts/write-launch-plist.py skills/taboc/scripts/run-with-timeout.py skills/taboc/scripts/extract-terminal-record.py skills/taboc/scripts/write-worker-prompt.py skills/taboc/scripts/check-model-ceiling.py; do
  python3 -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "${FILE}" \
    && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
done

bash skills/taboc/tests/test-opencode-worker.sh || FAIL=1

[ "${FAIL}" = 0 ] && echo "✅ taboc 契约通过" || echo "❌ taboc 契约失败"
exit "${FAIL}"
