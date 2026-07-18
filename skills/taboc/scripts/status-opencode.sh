#!/usr/bin/env bash
set -euo pipefail

REPO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "usage: status-opencode.sh --repo PATH" >&2; exit 2 ;;
  esac
done

[ -d "${REPO}/.taboc/opencode" ] || { echo "no opencode workers"; exit 0; }
printf 'worker\tstate\tmodel\tvariant\tattempt\tpid\n'
for STATUS_FILE in "${REPO}"/.taboc/opencode/*.status; do
  [ -f "${STATUS_FILE}" ] || continue
  WORKER_ID="$(basename "${STATUS_FILE}" .status)"
  IFS='|' read -r STATE MODEL VARIANT ATTEMPT < "${STATUS_FILE}"
  PID="$(cat "${REPO}/.taboc/opencode/${WORKER_ID}.pid" 2>/dev/null || true)"
  LABEL="$(cat "${REPO}/.taboc/opencode/${WORKER_ID}.label" 2>/dev/null || true)"
  if [ -n "${LABEL}" ] && command -v launchctl >/dev/null 2>&1; then
    LAUNCH_PID="$(launchctl list 2>/dev/null | awk -v label="${LABEL}" '$3 == label {print $1; exit}')"
    if [ -n "${LAUNCH_PID}" ]; then
      PID="${LAUNCH_PID}"
    fi
  fi
  if [ "${STATE}" = "running" ] || [ "${STATE}" = "launched" ]; then
    if [ -n "${PID}" ] && [ "${PID}" != "-" ] && ! kill -0 "${PID}" 2>/dev/null; then
      STATE="lost"
    elif [ -z "${PID}" ] && [ -z "${LABEL}" ] && [ ! -d "${REPO}/.taboc/opencode/${WORKER_ID}.run" ]; then
      STATE="lost"
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${WORKER_ID}" "${STATE}" "${MODEL}" "${VARIANT}" "${ATTEMPT}" "${PID:--}"
done
