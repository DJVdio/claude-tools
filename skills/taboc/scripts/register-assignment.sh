#!/usr/bin/env bash
set -euo pipefail

REPO=""
TASK=""
AGENT=""
POOL=""
MODEL=""
EFFORT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --pool) POOL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "${REPO}" ] && [ -n "${TASK}" ] && [ -n "${AGENT}" ] && [ -n "${POOL}" ] && [ -n "${MODEL}" ] && [ -n "${EFFORT}" ] \
  || { echo "missing assignment field" >&2; exit 2; }
for VALUE in "${TASK}" "${AGENT}" "${POOL}" "${MODEL}" "${EFFORT}"; do
  case "${VALUE}" in *$'\t'*|*$'\n'*) echo "assignment fields cannot contain tabs or newlines" >&2; exit 2 ;; esac
done
mkdir -p "${REPO}/.taboc"
printf '%s\t%s\t%s\t%s\t%s\n' "${TASK}" "${AGENT}" "${POOL}" "${MODEL}" "${EFFORT}" >> "${REPO}/.taboc/assignments.tsv"
