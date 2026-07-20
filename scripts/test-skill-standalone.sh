#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

check_links() {
  local SKILL_DIR="${1}"
  python3 - "${SKILL_DIR}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
text = (root / "SKILL.md").read_text(encoding="utf-8")
for target in re.findall(r"\]\(([^)#]+)", text):
    if "://" in target or target.startswith("<"):
        continue
    path = (root / target).resolve()
    if not path.exists() or root.resolve() not in [path, *path.parents]:
        raise SystemExit(f"invalid local skill link: {target}")
PY
}

for SKILL in tabb taboc; do
  cp -R "${ROOT_DIR}/skills/${SKILL}" "${TEST_ROOT}/${SKILL}"
  if grep -Eq 'skills/(ta|tabb|taboc)/|~/(\.claude|\.codex)/skills/' "${TEST_ROOT}/${SKILL}/SKILL.md"; then
    echo "${SKILL}/SKILL.md contains a cross-skill or install-location dependency" >&2
    exit 1
  fi
  check_links "${TEST_ROOT}/${SKILL}"
  for SCRIPT in "${TEST_ROOT}/${SKILL}"/*.sh "${TEST_ROOT}/${SKILL}"/scripts/*.sh; do
    [ -f "${SCRIPT}" ] && bash -n "${SCRIPT}"
  done
done

if grep -REq -- '--profile|profile=simple|simple_protocol|TABOC_MAX_ATTEMPTS' "${TEST_ROOT}/taboc/scripts"; then
  echo "taboc OpenCode runtime still contains the removed write profile or retry branch" >&2
  exit 1
fi
if grep -Eq 'ScheduleWakeup|TaskOutput|SendMessage|RETURN_REQUESTED' "${TEST_ROOT}/tabb/SKILL.md"; then
  echo "tabb still contains obsolete harness-specific coordination" >&2
  exit 1
fi

python3 -m json.tool "${TEST_ROOT}/tabb/evals/evals.json" >/dev/null
bash "${TEST_ROOT}/tabb/tests/test-routing-panel.sh"
bash "${TEST_ROOT}/taboc/tests/test-opencode-worker.sh"
echo "PASS: tabb and taboc run from isolated standalone copies"
