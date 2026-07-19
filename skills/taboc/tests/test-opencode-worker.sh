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

# Prompt generator carries the complete profile-specific protocol without loading it into SKILL.md.
python3 "${SKILL_DIR}/scripts/write-worker-prompt.py" \
  --output "${TEST_ROOT}/readonly.prompt" --repo "${REPO}" --branch main \
  --id prompt-readonly --profile readonly --task 'inspect auth' --validation 'rg auth'
grep -Fq '[HANDOFF] prompt-readonly →' "${TEST_ROOT}/readonly.prompt"
if grep -Eq '^  \[SEAL\]' "${TEST_ROOT}/readonly.prompt"; then
  echo "readonly prompt unexpectedly contains a SEAL output record" >&2
  exit 1
fi
python3 "${SKILL_DIR}/scripts/write-worker-prompt.py" \
  --output "${TEST_ROOT}/simple.prompt" --repo "${REPO}" --branch main \
  --id prompt-simple --profile simple --task 'fix typo' --validation 'npm test -- typo'
grep -Fq 'mkdir "${L}"' "${TEST_ROOT}/simple.prompt"
grep -Fq '[DONE] prompt-simple |' "${TEST_ROOT}/simple.prompt"
grep -Fq "[SEAL] ${REPO} |" "${TEST_ROOT}/simple.prompt"

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

# Empty/failed model discovery falls back to known free candidates instead of tried=0.
TABOC_MOCK_MODELS_EMPTY=1 bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
  --repo "${REPO}" --id scout-discovery --profile readonly --effort medium \
  --prompt-file "${TEST_ROOT}/prompt.txt"
grep -Fq 'done|opencode/deepseek-v4-flash-free|default|1' "${REPO}/.taboc/opencode/scout-discovery.status"

# A silent hung model hits the idle timeout and the next approved free model receives the task.
touch "${REPO}/.taboc/mock-deepseek-hang"
TABOC_ATTEMPT_TIMEOUT=1 TABOC_ATTEMPT_HARD_TIMEOUT=5 TABOC_STARTUP_HOLD=0 \
TABOC_MODELS='opencode/deepseek-v4-flash-free,opencode/nemotron-3-ultra-free' \
  bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
    --repo "${REPO}" --id scout-timeout --profile readonly --effort high \
    --prompt-file "${TEST_ROOT}/prompt.txt"
rm "${REPO}/.taboc/mock-deepseek-hang"
grep -Fq 'done|opencode/nemotron-3-ultra-free|high|2' "${REPO}/.taboc/opencode/scout-timeout.status"
grep -Fq 'TabocAttemptIdleTimeout' "${REPO}/.taboc/opencode/attempts/scout-timeout.1.log"

# Productive output resets the idle timer, so an active task can exceed the old wall-clock limit.
touch "${REPO}/.taboc/mock-active-long"
TABOC_ATTEMPT_TIMEOUT=1 TABOC_ATTEMPT_HARD_TIMEOUT=5 TABOC_STARTUP_HOLD=0 \
TABOC_MODELS='opencode/deepseek-v4-flash-free' TABOC_MAX_ATTEMPTS=1 \
  bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
    --repo "${REPO}" --id scout-active --profile readonly --effort high \
    --prompt-file "${TEST_ROOT}/prompt.txt"
rm "${REPO}/.taboc/mock-active-long"
grep -Fq 'done|opencode/deepseek-v4-flash-free|high|1' "${REPO}/.taboc/opencode/scout-active.status"
if grep -Fq 'TabocAttemptIdleTimeout' "${REPO}/.taboc/opencode/attempts/scout-active.1.log"; then
  echo "active worker incorrectly hit idle timeout" >&2
  exit 1
fi

# Continuous chatter cannot bypass the hard wall-clock limit.
touch "${REPO}/.taboc/mock-active-long"
TABOC_ATTEMPT_TIMEOUT=5 TABOC_ATTEMPT_HARD_TIMEOUT=1 TABOC_STARTUP_HOLD=0 \
TABOC_MODELS='opencode/deepseek-v4-flash-free,opencode/nemotron-3-ultra-free' \
  bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
    --repo "${REPO}" --id scout-hard-timeout --profile readonly --effort high \
    --prompt-file "${TEST_ROOT}/prompt.txt"
rm "${REPO}/.taboc/mock-active-long"
grep -Fq 'TabocAttemptHardTimeout' "${REPO}/.taboc/opencode/attempts/scout-hard-timeout.1.log"
grep -Fq 'done|opencode/nemotron-3-ultra-free|high|2' "${REPO}/.taboc/opencode/scout-hard-timeout.status"

# Exact terminal records printed only in final JSON are safely materialized into journal.
touch "${REPO}/.taboc/mock-output-only"
bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
  --repo "${REPO}" --id scout-output --profile readonly --effort medium \
  --prompt-file "${TEST_ROOT}/prompt.txt"
rm "${REPO}/.taboc/mock-output-only"
grep -Fq '[HANDOFF] scout-output → root | recovered from final output' "${REPO}/.taboc/journal.md"
grep -Fq 'done|opencode/deepseek-v4-flash-free|medium|1' "${REPO}/.taboc/opencode/scout-output.status"

# Concurrent model queries and run cold starts are briefly serialized to avoid OpenCode's shared SQLite lock.
TABOC_MOCK_DB_LOCK_DIR="${REPO}/.taboc/mock-db-lock" \
TABOC_MOCK_RUN_DB_LOCK_DIR="${REPO}/.taboc/mock-run-db-lock" TABOC_STARTUP_HOLD=0.3 \
  bash "${SKILL_DIR}/scripts/opencode-worker.sh" --repo "${REPO}" --id concurrent-a \
    --profile readonly --effort medium --prompt-file "${TEST_ROOT}/prompt.txt" &
CONCURRENT_A=$!
TABOC_MOCK_DB_LOCK_DIR="${REPO}/.taboc/mock-db-lock" \
TABOC_MOCK_RUN_DB_LOCK_DIR="${REPO}/.taboc/mock-run-db-lock" TABOC_STARTUP_HOLD=0.3 \
  bash "${SKILL_DIR}/scripts/opencode-worker.sh" --repo "${REPO}" --id concurrent-b \
    --profile readonly --effort medium --prompt-file "${TEST_ROOT}/prompt.txt" &
CONCURRENT_B=$!
wait "${CONCURRENT_A}"
wait "${CONCURRENT_B}"
grep -Fq 'done|' "${REPO}/.taboc/opencode/concurrent-a.status"
grep -Fq 'done|' "${REPO}/.taboc/opencode/concurrent-b.status"

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

# LaunchAgent receives model and attempt overrides from the launcher environment.
rm "${REPO}/.taboc/mock-sleep"
TABOC_MODELS=opencode/nemotron-3-ultra-free TABOC_MAX_ATTEMPTS=1 \
TABOC_ATTEMPT_TIMEOUT=7 TABOC_ATTEMPT_HARD_TIMEOUT=11 TABOC_STARTUP_HOLD=0 \
  bash "${SKILL_DIR}/scripts/launch-opencode.sh" \
    --repo "${REPO}" --id scout-env --profile readonly --effort medium \
    --prompt-file "${TEST_ROOT}/prompt.txt" >/dev/null
for _ in $(seq 1 30); do
  grep -Fq 'done|opencode/nemotron-3-ultra-free|medium|1' "${REPO}/.taboc/opencode/scout-env.status" 2>/dev/null && break
  sleep 0.1
done
grep -Fq 'done|opencode/nemotron-3-ultra-free|medium|1' "${REPO}/.taboc/opencode/scout-env.status"
grep -Fq 'opencode/nemotron-3-ultra-free|medium|' "${REPO}/.taboc/mock-calls.log"
grep -Fq '|opencode/nemotron-3-ultra-free|1|7|11' "${REPO}/.taboc/mock-calls.log"

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
| stale-worker | stale-worker | opencode | running |
EOF
bash "${SKILL_DIR}/scripts/register-assignment.sh" --repo "${REPO}" --task risky-fix \
  --agent premium-one --pool premium --model luna --effort high \
  --main-model luna --main-effort max
printf 'running|opencode/deepseek-v4-flash-free|high|1\n' > "${REPO}/.taboc/opencode/stale-worker.status"
printf '99999999\n' > "${REPO}/.taboc/opencode/stale-worker.pid"
PANEL="$(bash "${SKILL_DIR}/scripts/task-panel.sh" --repo "${REPO}")"
printf '%s\n' "${PANEL}" | grep -Fq '| scout-two | scout-two | opencode | opencode/deepseek-v4-flash-free | medium | done |'
printf '%s\n' "${PANEL}" | grep -Fq '| risky-fix | premium-one | premium | luna | high | running |'
printf '%s\n' "${PANEL}" | grep -Fq '| stale-worker | stale-worker | opencode | opencode/deepseek-v4-flash-free | high | lost |'

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

echo "PASS: adaptive idle/hard timeout, fallback, concurrent startup, env forwarding, terminal recovery, premium ceiling, live task panel"
