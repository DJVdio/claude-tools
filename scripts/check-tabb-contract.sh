#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "${0}")/.."

SKILL="skills/tabb/SKILL.md"
FAIL=0
ok()  { printf '  ✅ %s\n' "${1}"; }
bad() { printf '  ❌ %s\n' "${1}"; FAIL=1; }
need() {
  grep -Fq "${1}" "${SKILL}" && ok "${2}" || bad "${2}"
}

echo "══ tabb 体积与核心契约 ══"
BYTES="$(wc -c < "${SKILL}" | tr -d ' ')"
LINES="$(wc -l < "${SKILL}" | tr -d ' ')"
[ "${BYTES}" -le 9000 ] && ok "SKILL.md ${BYTES} bytes ≤ 9000" || bad "SKILL.md 过大：${BYTES} bytes"
[ "${LINES}" -le 150 ] && ok "SKILL.md ${LINES} lines ≤ 150" || bad "SKILL.md 过长：${LINES} lines"

need '仅在用户显式调用 `/tabb`' "只手动触发"
need '不读取其他 skill' "独立运行"
need 'mkdir "${L}" 2>/dev/null' "文件级原子锁"
need '[HANDOFF] scout → impl' "黑板交接"
need '[DECISION] agent' "高风险决策上抛"
need 'journal 是完成权威' "单一完成门禁"
need '只读默认 medium' "只读默认 medium"
need '机械检索/事实收集才 low' "仅机械只读降到 low"
need '`work`：spawn 省略 `model` 和 `reasoning_effort`' "写入任务继承主档"
need 'spawn 成功后才把 board 标为 `doing`' "面板不虚报在途"
need 'seal-from-journal.sh --dry-run' "收口预检"
need '只从 `[SEAL]` 生成白名单' "机器可读白名单"
need '禁止 force push' "禁止 force push"
need '[references/failures.md](references/failures.md)' "异常手册按需加载"

if grep -Eq 'ScheduleWakeup|TaskOutput|SendMessage|RETURN_REQUESTED|~/(\.claude|\.codex)/skills/' "${SKILL}"; then
  bad "仍含过时运行时或安装路径耦合"
else
  ok "无过时运行时或安装路径耦合"
fi

for FILE in skills/tabb/*.sh skills/tabb/scripts/*.sh; do
  [ -f "${FILE}" ] && { bash -n "${FILE}" && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"; }
done
for FILE in skills/tabb/scripts/*.py; do
  python3 -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "${FILE}" \
    && ok "${FILE} 语法通过" || bad "${FILE} 语法错误"
done
python3 -m json.tool skills/tabb/evals/evals.json >/dev/null || bad "evals.json 非法"
bash skills/tabb/tests/test-routing-panel.sh || FAIL=1

[ "${FAIL}" = 0 ] && echo "✅ tabb 契约通过" || echo "❌ tabb 契约失败"
exit "${FAIL}"
