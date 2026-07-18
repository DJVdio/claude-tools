#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  for LABEL_FILE in "${REPO}"/.taboc/opencode/*.label; do
    [ -f "${LABEL_FILE}" ] || continue
    launchctl bootout "gui/$(id -u)/$(cat "${LABEL_FILE}")" 2>/dev/null || true
  done
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT
MOCK_BIN="${TEST_ROOT}/bin"
REPO="${TEST_ROOT}/repo"
mkdir -p "${MOCK_BIN}" "${REPO}/.taboc/locks"
cp "${SKILL_DIR}/tests/fixtures/opencode" "${MOCK_BIN}/opencode"
chmod +x "${MOCK_BIN}/opencode"
touch "${REPO}/.taboc/journal.md"
printf '%s\n' 'Return done.' > "${TEST_ROOT}/prompt.txt"
export PATH="${MOCK_BIN}:${PATH}"
export TABOC_OPENCODE_BIN="${MOCK_BIN}/opencode"
touch "${REPO}/.taboc/mock-deepseek-fail"

bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
  --repo "${REPO}" --id scout-one --profile readonly --effort xhigh \
  --prompt-file "${TEST_ROOT}/prompt.txt"

grep -Fq 'opencode/deepseek-v4-flash-free|max|' "${REPO}/.taboc/mock-calls.log"
grep -Fq 'opencode/nemotron-3-ultra-free|high|' "${REPO}/.taboc/mock-calls.log"
grep -Fq '".taboc/journal.md":"allow"' "${REPO}/.taboc/mock-calls.log"
grep -Fq '[MODEL_FALLBACK] scout-one' "${REPO}/.taboc/journal.md"
grep -Fq 'done|opencode/nemotron-3-ultra-free|high|2' "${REPO}/.taboc/opencode/scout-one.status"

rm "${REPO}/.taboc/mock-deepseek-fail"
touch "${REPO}/.taboc/mock-sleep"
bash "${SKILL_DIR}/scripts/launch-opencode.sh" --check | grep -Fq "ready|${MOCK_BIN}/opencode|"
bash "${SKILL_DIR}/scripts/launch-opencode.sh" \
  --repo "${REPO}" --id scout-two --profile readonly --effort medium \
  --prompt-file "${TEST_ROOT}/prompt.txt" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PID="$(cat "${REPO}/.taboc/opencode/scout-two.pid" 2>/dev/null || true)"
  [ -n "${PID}" ] && kill -0 "${PID}" 2>/dev/null && break
  sleep 0.1
done
[ -n "${PID:-}" ] && kill -0 "${PID}" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  grep -Fq 'done|opencode/deepseek-v4-flash-free|medium|1' "${REPO}/.taboc/opencode/scout-two.status" 2>/dev/null && break
  sleep 0.1
done
grep -Fq 'done|opencode/deepseek-v4-flash-free|medium|1' "${REPO}/.taboc/opencode/scout-two.status"
[ ! -d "${REPO}/.taboc/opencode/scout-two.run" ]

# KeepAlive=false: a completed job must not be relaunched.
SCOUT_TWO_CALLS="$(grep -Fc 'opencode/deepseek-v4-flash-free|medium|' "${REPO}/.taboc/mock-calls.log")"
sleep 1.2
[ "$(grep -Fc 'opencode/deepseek-v4-flash-free|medium|' "${REPO}/.taboc/mock-calls.log")" = "${SCOUT_TWO_CALLS}" ]

# A task body mentioning quota-like words is not an OpenCode error event.
printf '%s\n' '{"type":"text","text":"402 429 quota Capacity overload credit"}' > "${TEST_ROOT}/clean.jsonl"
[ "$(python3 "${SKILL_DIR}/scripts/classify-opencode-log.py" "${TEST_ROOT}/clean.jsonl")" = clean ]
printf '%s\n' '{"type":"error","error":"429 quota exceeded"}' > "${TEST_ROOT}/retryable.jsonl"
[ "$(python3 "${SKILL_DIR}/scripts/classify-opencode-log.py" "${TEST_ROOT}/retryable.jsonl")" = retryable ]

# The panel exposes requested/actual OpenCode routing and exact premium routing.
cat > "${REPO}/.taboc/board.md" <<'EOF'
| Task | Claimed By | Pool | Status |
|---|---|---|---|
| scout-two | scout-two | opencode | claimed |
| risky-fix | premium-one | premium | running |
EOF
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${REPO}" --task risky-fix \
  --agent premium-one --pool premium --model luna --effort high \
  --main-model luna --main-effort max
PANEL="$(bash "${SKILL_DIR}/scripts/task-panel.sh" --repo "${REPO}")"
printf '%s\n' "${PANEL}" | grep -Fq '| scout-two | scout-two | opencode | opencode/deepseek-v4-flash-free | medium | done |'
printf '%s\n' "${PANEL}" | grep -Fq '| risky-fix | premium-one | premium | luna | high | running |'

# A terminal journal record prevents accidental duplicate launches.
if bash "${SKILL_DIR}/scripts/launch-opencode.sh" \
  --repo "${REPO}" --id scout-two --profile readonly --effort medium \
  --prompt-file "${TEST_ROOT}/prompt.txt" >/dev/null 2>&1; then
  echo "duplicate launch unexpectedly succeeded" >&2
  exit 1
fi

# Lower effort cannot justify upgrading the child to a stronger model family.
if bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${REPO}" --task model-inversion \
  --agent premium-sol --pool premium --model sol --effort high \
  --main-model luna --main-effort max >/dev/null 2>&1; then
  echo "Luna main unexpectedly spawned a Sol child" >&2
  exit 1
fi
if bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${REPO}" --task effort-inversion \
  --agent premium-max --pool premium --model luna --effort max \
  --main-model luna --main-effort high >/dev/null 2>&1; then
  echo "high-effort main unexpectedly spawned a max-effort premium child" >&2
  exit 1
fi

echo "PASS: fallback, structured errors, one-shot launchd, duplicate guard, premium parent ceiling, model-effort panel"
