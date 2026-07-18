#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO=""
WORKER_ID=""
PROFILE=""
EFFORT=""
PROMPT_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --id) WORKER_ID="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "${REPO}" ] && [ -n "${WORKER_ID}" ] && [ -f "${PROMPT_FILE}" ] || { echo "missing or invalid arguments" >&2; exit 2; }
case "${REPO}" in /*) ;; *) echo "repo must be an absolute path" >&2; exit 2 ;; esac
case "${WORKER_ID}" in *[!A-Za-z0-9._-]*) echo "invalid worker id" >&2; exit 2 ;; esac
case "${PROFILE}" in readonly|simple) ;; *) echo "invalid profile" >&2; exit 2 ;; esac
case "${EFFORT}" in low|medium|high|max|xhigh) ;; *) echo "invalid effort" >&2; exit 2 ;; esac
STATE_DIR="${REPO}/.taboc/opencode"
RUN_LOCK="${STATE_DIR}/${WORKER_ID}.run"
mkdir -p "${STATE_DIR}/attempts"
if ! mkdir "${RUN_LOCK}" 2>/dev/null; then
  echo "worker already launched: ${WORKER_ID}" >&2
  exit 3
fi

LOG_FILE="${STATE_DIR}/${WORKER_ID}.launcher.log"
printf 'launched|pending|pending|0\n' > "${STATE_DIR}/${WORKER_ID}.status"
(
  trap 'rmdir "${RUN_LOCK}" 2>/dev/null || true' EXIT
  bash "${SCRIPT_DIR}/opencode-worker.sh" --repo "${REPO}" --id "${WORKER_ID}" --profile "${PROFILE}" --effort "${EFFORT}" --prompt-file "${PROMPT_FILE}"
) > "${LOG_FILE}" 2>&1 &
PID=$!
printf '%s\n' "${PID}" > "${STATE_DIR}/${WORKER_ID}.pid"
echo "launched ${WORKER_ID} pid=${PID} log=${LOG_FILE}"
