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
| 修复登录 | impl-auth | open |
| 等待产品确认 | — | blocked |
EOF

route() {
  python3 "${SKILL_DIR}/scripts/route-task.py" --class "${1}" \
    --current-model "${2}" --current-effort "${3}"
}

[ "$(route readonly gpt-5.6-sol max)" = $'premium\tgpt-5.6-sol\tlow' ]
[ "$(route work gpt-5.6-sol max)" = $'premium\tgpt-5.6-sol\tmax' ]
[ "$(route readonly gpt-5.6-luna medium)" = $'premium\tgpt-5.6-luna\tlow' ]
[ "$(route work gpt-5.6-luna medium)" = $'premium\tgpt-5.6-luna\tmedium' ]
if route simple gpt-5.6-luna medium >/dev/null 2>&1; then
  echo "route unexpectedly accepts the removed five-class model routing" >&2
  exit 1
fi

grep -Fq '所有 worker 使用当前主 agent 模型' "${SKILL_DIR}/SKILL.md"
grep -Fq '`work`：spawn 省略 `model` 和 `reasoning_effort`' "${SKILL_DIR}/SKILL.md"
grep -Fq '`readonly`：spawn 省略 `model`，传 `reasoning_effort="low"`' "${SKILL_DIR}/SKILL.md"
grep -Fq 'spawn 成功后才把 board 改为 `doing`' "${SKILL_DIR}/SKILL.md"
if grep -Fq '固定五档' "${SKILL_DIR}/SKILL.md"; then
  echo "skill still contains the old five-class model routing" >&2
  exit 1
fi

bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 查调用链 --agent scout-auth --role readonly --model gpt-5.6-sol --effort low
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 修复登录 --agent impl-auth --role implementation --model gpt-5.6-sol --effort max

PANEL="$(bash "${SKILL_DIR}/scripts/task-panel.sh" --repo "${TEST_ROOT}")"
printf '%s\n' "${PANEL}" | grep -Fq '| 查调用链 | scout-auth | readonly | gpt-5.6-sol | low | doing |'
printf '%s\n' "${PANEL}" | grep -Fq '| 修复登录 | impl-auth | implementation | gpt-5.6-sol | max | open |'
printf '%s\n' "${PANEL}" | grep -Fq '| 等待产品确认 | — | not-dispatched | not-dispatched | not-dispatched | blocked |'

echo "PASS: tabb inherits current model/effort and lowers readonly effort"
