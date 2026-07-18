#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  for LABEL_FILE in "${REPO}"/.taboc/opencode/*.label; do
    [ -f "${LABEL_FILE}" ] || continue
    launchctl remove "$(cat "${LABEL_FILE}")" 2>/dev/null || true
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

echo "PASS: variant probing, free-model fallback, readonly permissions, launchd survival"
