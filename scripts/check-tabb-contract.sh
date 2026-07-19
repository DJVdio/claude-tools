#!/usr/bin/env bash
# tabb 瘦身回归：限制 prompt 体积，确保核心编排能力仍在。
set -uo pipefail
cd "$(dirname "${0}")/.."

SKILL=skills/tabb/SKILL.md
EVALS=skills/tabb/evals/evals.json
FAIL=0

ok()  { printf '  ✅ %s\n' "${1}"; }
bad() { printf '  ❌ %s\n' "${1}"; FAIL=1; }
need() {
  if grep -Fq "${1}" "${SKILL}"; then ok "${2}"; else bad "${2}"; fi
}

echo "══ 1. token 预算代理指标 ══"
BYTES=$(wc -c < "${SKILL}" | tr -d ' ')
LINES=$(wc -l < "${SKILL}" | tr -d ' ')
if [ "${BYTES}" -le 14000 ]; then ok "SKILL.md ${BYTES} bytes ≤ 14000"; else bad "SKILL.md ${BYTES} bytes > 14000"; fi
if [ "${LINES}" -le 220 ]; then ok "SKILL.md ${LINES} lines ≤ 220"; else bad "SKILL.md ${LINES} lines > 220"; fi

echo "══ 2. 六类行为契约 ══"
need 'mkdir "${L}" 2>/dev/null' "文件争用：mkdir 原子锁"
need '[DECISION] <你> | <问题>' "生产/设计决策：DECISION 上抛"
need '[HANDOFF] <你> → <下游>' "复杂任务：HANDOFF 交接"
need '[RETURN_REQUESTED]' "缺 return：单次补催记账"
need '禁止重复催或 respawn' "完工 idle：禁止重复派单"
need '不得复用旧 PASS' "分层测试：本批次 VERIFY 门禁"
need 'ScheduleWakeup' "持续回报：自驱轮询"
need 'TaskOutput' "进度：读取真实里程碑"
need '出现 malformed 立即停' "派单：malformed 防失准"
need '路由只认固定五档' "模型：只认固定五档"
need 'gpt-5.6-luna / low' "只读：Luna-low"
need 'gpt-5.6-luna / medium' "简单：Luna-medium"
need 'gpt-5.6-luna / max' "短复杂：Luna-max"
need 'gpt-5.6-sol / medium' "长复杂：Sol-medium"
need 'gpt-5.6-sol / high' "非常复杂：Sol-high"
need 'route-task.py --class' "派发：强制运行固定路由脚本"
need 'task-panel.sh --repo' "进度：任务面板展示调度"
need 'Model / Effort' "面板：显示模型与思考程度"
need '不得手写 assignments 绕过脚本' "门禁：禁止伪造登记"

echo "══ 3. 收口与自包含契约 ══"
need 'seal-from-journal.sh --dry-run' "收口预检脚本"
need '白名单只读 `[SEAL]`' "白名单禁止解析 DONE"
need '禁 force push' "禁止 force push"
need 'tabb 独立可安装，不依赖 ta 文件或正文' "独立安装声明"
if grep -q 'skills/ta/' "${SKILL}"; then bad "存在 ta 文件路径依赖"; else ok "无 ta 文件路径依赖"; fi

echo "══ 4. eval 基准 ══"
if python3 - "${EVALS}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
expected = {
    "shared-file-contention",
    "decision-escalation",
    "handoff-via-blackboard",
    "journal-completion-with-return-fallback",
    "completed-idle-does-not-respawn",
    "parallel-targeted-tests-full-suite-at-seal",
}
actual = {case["name"] for case in data["evals"]}
assert actual == expected, (actual, expected)
assert "mkdir" in data["evals"][0]["expected_output"]
assert "读→锁→回读校验" not in data["evals"][0]["expected_output"]
PY
then ok "6 条 eval 完整，原子锁基准已更新"; else bad "eval 缺失、JSON 错误或仍含旧锁协议"; fi

echo "══ 5. 固定路由与任务面板 ══"
for FILE in skills/tabb/scripts/register-assignment.sh skills/tabb/scripts/task-panel.sh; do
  bash -n "${FILE}" && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
done
for FILE in skills/tabb/scripts/route-task.py skills/tabb/scripts/task-panel.py; do
  python3 -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "${FILE}" \
    && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
done
bash skills/tabb/tests/test-routing-panel.sh || FAIL=1

echo
[ "${FAIL}" = 0 ] && echo "✅ tabb 体积与能力契约通过" || echo "❌ tabb 回归失败"
exit "${FAIL}"
