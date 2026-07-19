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

bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 查调用链 --agent scout-auth --role readonly \
  --model gpt-5.6-terra --effort medium --main-model gpt-5.6-luna --main-effort max
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 修复登录 --agent impl-auth --role implementation \
  --model inherit-main --effort inherit-main

if bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 截图复现 --agent bad-same-high --role implementation \
  --model gpt-5.6-sol --effort high --main-model gpt-5.6-sol --main-effort high >/dev/null 2>&1; then
  echo "explicit same-model high unexpectedly accepted via a falsely reported main high" >&2
  exit 1
fi

if bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 越级模型 --agent bad-model --role readonly \
  --model gpt-5.6-sol --effort low --main-model gpt-5.6-luna --main-effort max >/dev/null 2>&1; then
  echo "stronger child model unexpectedly accepted" >&2
  exit 1
fi
if bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 越级思考 --agent bad-effort --role readonly \
  --model gpt-5.6-terra --effort max --main-model gpt-5.6-luna --main-effort high >/dev/null 2>&1; then
  echo "stronger child effort unexpectedly accepted" >&2
  exit 1
fi
if bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${TEST_ROOT}" \
  --task 未知跨系 --agent unknown-model --role readonly \
  --model vendor-fast --effort low --main-model vendor-pro --main-effort high >/dev/null 2>&1; then
  echo "unprovable cross-series downgrade unexpectedly accepted" >&2
  exit 1
fi

PANEL="$(bash "${SKILL_DIR}/scripts/task-panel.sh" --repo "${TEST_ROOT}")"
printf '%s\n' "${PANEL}" | grep -Fq '| 查调用链 | scout-auth | readonly | gpt-5.6-terra | medium | doing |'
printf '%s\n' "${PANEL}" | grep -Fq '| 修复登录 | impl-auth | implementation | inherit-main | inherit-main | open |'
printf '%s\n' "${PANEL}" | grep -Fq '| 等待产品确认 | — | not-dispatched | not-dispatched | not-dispatched | blocked |'

echo "PASS: inheritance and strict downgrades accepted; equal, stronger, or unprovable overrides rejected"
