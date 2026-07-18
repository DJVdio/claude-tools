#!/usr/bin/env bash
set -euo pipefail

REPO=""
TASK=""
AGENT=""
POOL=""
MODEL=""
EFFORT=""
MAIN_MODEL=""
MAIN_EFFORT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --pool) POOL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --main-model) MAIN_MODEL="$2"; shift 2 ;;
    --main-effort) MAIN_EFFORT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "${POOL}" = premium ]; then
  [ -n "${MAIN_MODEL}" ] && [ -n "${MAIN_EFFORT}" ] \
    || { echo "premium assignments require --main-model and --main-effort" >&2; exit 2; }
  [ "${MODEL}" = "${MAIN_MODEL}" ] \
    || { echo "premium child must inherit the main model; refusing ${MAIN_MODEL} -> ${MODEL}" >&2; exit 2; }
  EFFECTIVE_EFFORT="$(bash "$(cd "$(dirname "$0")" && pwd)/cap-effort.sh" "${EFFORT}" "${MAIN_EFFORT}")"
  [ "${EFFECTIVE_EFFORT}" = "${EFFORT}" ] \
    || { echo "premium child effort exceeds main effort: ${EFFORT} > ${MAIN_EFFORT}" >&2; exit 2; }
fi

[ -d "${REPO}" ] && [ -n "${TASK}" ] && [ -n "${AGENT}" ] && [ -n "${POOL}" ] && [ -n "${MODEL}" ] && [ -n "${EFFORT}" ] \
  || { echo "missing assignment field" >&2; exit 2; }
for VALUE in "${TASK}" "${AGENT}" "${POOL}" "${MODEL}" "${EFFORT}"; do
  case "${VALUE}" in *$'\t'*|*$'\n'*) echo "assignment fields cannot contain tabs or newlines" >&2; exit 2 ;; esac
done
mkdir -p "${REPO}/.taboc"
printf '%s\t%s\t%s\t%s\t%s\n' "${TASK}" "${AGENT}" "${POOL}" "${MODEL}" "${EFFORT}" >> "${REPO}/.taboc/assignments.tsv"
