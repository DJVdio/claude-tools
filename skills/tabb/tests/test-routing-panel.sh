#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${0}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT
mkdir -p "${TEST_ROOT}/.tabb"
cat > "${TEST_ROOT}/.tabb/board.md" <<'EOF'
| 任务 | 认领者 | 状态 |
|---|---|---|
| 查调用链 | scout-auth | doing |
| 查版本号 | scout-version | doing |
| 修复登录 | impl-auth | open |
| 等待产品确认 | — | blocked |
EOF

route() {
  python3 "${SKILL_DIR}/scripts/route-task.py" --class "${1}" \
    --current-model "${2}" --current-effort "${3}"
}

[ "$(route readonly gpt-5.6-sol max)" = $'premium\tgpt-5.6-sol\tmedium' ]
[ "$(route readonly-low gpt-5.6-sol max)" = $'premium\tgpt-5.6-sol\tlow' ]
[ "$(route work gpt-5.6-sol max)" = $'premium\tgpt-5.6-sol\tmax' ]
[ "$(route readonly gpt-5.6-luna medium)" = $'premium\tgpt-5.6-luna\tmedium' ]
[ "$(route readonly-low gpt-5.6-luna medium)" = $'premium\tgpt-5.6-luna\tlow' ]
[ "$(route work gpt-5.6-luna medium)" = $'premium\tgpt-5.6-luna\tmedium' ]
if route simple gpt-5.6-luna medium >/dev/null 2>&1; then
  echo "route unexpectedly accepts the removed five-class model routing" >&2
  exit 1
fi

grep -Fq '派发均继承当前模型' "${SKILL_DIR}/SKILL.md"
grep -Fq '`work`：spawn 省略 `model` 和 `reasoning_effort`' "${SKILL_DIR}/SKILL.md"
grep -Fq '只读默认 medium' "${SKILL_DIR}/SKILL.md"
grep -Fq '机械检索/事实收集才 low' "${SKILL_DIR}/SKILL.md"
grep -Fq 'spawn 成功后才把 board 标为 `doing`' "${SKILL_DIR}/SKILL.md"
if grep -Fq '固定五档' "${SKILL_DIR}/SKILL.md"; then
  echo "skill still contains the old five-class model routing" >&2
  exit 1
fi

bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 查调用链 --agent scout-auth --role readonly --model gpt-5.6-sol --effort medium
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 查版本号 --agent scout-version --role readonly --model gpt-5.6-sol --effort low
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 修复登录 --agent impl-auth --role implementation --model gpt-5.6-sol --effort max

PANEL="$(bash "${SKILL_DIR}/scripts/task-panel.sh" --repo "${TEST_ROOT}")"
printf '%s\n' "${PANEL}" | grep -Fq '| 查调用链 | scout-auth | readonly | gpt-5.6-sol | medium | doing |'
printf '%s\n' "${PANEL}" | grep -Fq '| 查版本号 | scout-version | readonly | gpt-5.6-sol | low | doing |'
printf '%s\n' "${PANEL}" | grep -Fq '| 修复登录 | impl-auth | implementation | gpt-5.6-sol | max | open |'
printf '%s\n' "${PANEL}" | grep -Fq '| 等待产品确认 | — | not-dispatched | not-dispatched | not-dispatched | blocked |'

echo "PASS: tabb inherits current model, defaults readonly to medium, and lowers mechanical lookup"
