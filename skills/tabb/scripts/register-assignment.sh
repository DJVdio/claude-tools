#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

REPO=""
TASK=""
AGENT=""
ROLE=""
MODEL=""
EFFORT=""
MAIN_MODEL=""
MAIN_EFFORT=""
while [ "${#}" -gt 0 ]; do
  case "${1}" in
    --repo) REPO="${2}"; shift 2 ;;
    --task) TASK="${2}"; shift 2 ;;
    --agent) AGENT="${2}"; shift 2 ;;
    --role) ROLE="${2}"; shift 2 ;;
    --model) MODEL="${2}"; shift 2 ;;
    --effort) EFFORT="${2}"; shift 2 ;;
    --main-model) MAIN_MODEL="${2}"; shift 2 ;;
    --main-effort) MAIN_EFFORT="${2}"; shift 2 ;;
    *) echo "unknown argument: ${1}" >&2; exit 2 ;;
  esac
done

[ -d "${REPO}" ] && [ -n "${TASK}" ] && [ -n "${AGENT}" ] && [ -n "${ROLE}" ] \
  && [ -n "${MODEL}" ] && [ -n "${EFFORT}" ] \
  || { echo "missing assignment field" >&2; exit 2; }
for VALUE in "${TASK}" "${AGENT}" "${ROLE}" "${MODEL}" "${EFFORT}"; do
  case "${VALUE}" in *$'\t'*|*$'\n'*) echo "assignment fields cannot contain tabs or newlines" >&2; exit 2 ;; esac
done

python3 "${SCRIPT_DIR}/check-model-ceiling.py" \
  --model "${MODEL}" --effort "${EFFORT}" \
  --main-model "${MAIN_MODEL}" --main-effort "${MAIN_EFFORT}" --strict-overrides
mkdir -p "${REPO}/.tabb"
printf '%s\t%s\t%s\t%s\t%s\n' "${TASK}" "${AGENT}" "${ROLE}" "${MODEL}" "${EFFORT}" \
  >> "${REPO}/.tabb/assignments.tsv"
