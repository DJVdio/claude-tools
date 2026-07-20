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
  python3 "${SKILL_DIR}/scripts/route-task.py" --class "${1}"
}

[ "$(route readonly)" = $'premium\tgpt-5.6-luna\tlow' ]
[ "$(route simple)" = $'premium\tgpt-5.6-luna\tmedium' ]
[ "$(route complex-short)" = $'premium\tgpt-5.6-luna\tmax' ]
[ "$(route complex-long)" = $'premium\tgpt-5.6-sol\tmedium' ]
[ "$(route very-complex)" = $'premium\tgpt-5.6-sol\thigh' ]

grep -Fq '规模只决定拆单，不决定模型' "${SKILL_DIR}/SKILL.md"
grep -Fq 'Sol 必须有具体理由' "${SKILL_DIR}/SKILL.md"
if grep -Eq '^\| `complex-long` \|.*(30 分钟|4 个以上业务文件)' "${SKILL_DIR}/SKILL.md"; then
  echo "complex-long unexpectedly uses task size as a routing signal" >&2
  exit 1
fi

bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 查调用链 --agent scout-auth --role readonly --model gpt-5.6-luna --effort low
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 修复登录 --agent impl-auth --role simple --model gpt-5.6-luna --effort medium

PANEL="$(bash "${SKILL_DIR}/scripts/task-panel.sh" --repo "${TEST_ROOT}")"
printf '%s\n' "${PANEL}" | grep -Fq '| 查调用链 | scout-auth | readonly | gpt-5.6-luna | low | doing |'
printf '%s\n' "${PANEL}" | grep -Fq '| 修复登录 | impl-auth | simple | gpt-5.6-luna | medium | open |'
printf '%s\n' "${PANEL}" | grep -Fq '| 等待产品确认 | — | not-dispatched | not-dispatched | not-dispatched | blocked |'

echo "PASS: tabb fixed five-class routing and panel"
