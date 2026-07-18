#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT
MOCK_BIN="${TEST_ROOT}/bin"
REPO="${TEST_ROOT}/repo"
mkdir -p "${MOCK_BIN}" "${REPO}/.taboc/locks"
cp "${SKILL_DIR}/tests/fixtures/opencode" "${MOCK_BIN}/opencode"
chmod +x "${MOCK_BIN}/opencode"
touch "${REPO}/.taboc/journal.md"
printf '%s\n' 'Return done.' > "${TEST_ROOT}/prompt.txt"
export PATH="${MOCK_BIN}:${PATH}"
export MOCK_CALLS="${TEST_ROOT}/calls.log"
export MOCK_DEEPSEEK_FAIL=1

bash "${SKILL_DIR}/scripts/opencode-worker.sh" \
  --repo "${REPO}" --id scout-one --profile readonly --effort xhigh \
  --prompt-file "${TEST_ROOT}/prompt.txt"

grep -Fq 'opencode/deepseek-v4-flash-free|max|' "${MOCK_CALLS}"
grep -Fq 'opencode/nemotron-3-ultra-free|high|' "${MOCK_CALLS}"
grep -Fq '".taboc/journal.md":"allow"' "${MOCK_CALLS}"
grep -Fq '[MODEL_FALLBACK] scout-one' "${REPO}/.taboc/journal.md"
grep -Fq 'done|opencode/nemotron-3-ultra-free|high|2' "${REPO}/.taboc/opencode/scout-one.status"

export MOCK_DEEPSEEK_FAIL=0
bash "${SKILL_DIR}/scripts/launch-opencode.sh" \
  --repo "${REPO}" --id scout-two --profile readonly --effort medium \
  --prompt-file "${TEST_ROOT}/prompt.txt" >/dev/null
for _ in 1 2 3 4 5; do
  grep -Fq 'done|opencode/deepseek-v4-flash-free|medium|1' "${REPO}/.taboc/opencode/scout-two.status" 2>/dev/null && break
  sleep 0.1
done
grep -Fq 'done|opencode/deepseek-v4-flash-free|medium|1' "${REPO}/.taboc/opencode/scout-two.status"

echo "PASS: variant probing, free-model fallback, readonly permissions, background launch"
