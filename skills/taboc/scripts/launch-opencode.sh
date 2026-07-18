#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

resolve_opencode_bin() {
  local CANDIDATE=""
  if [ -n "${TABOC_OPENCODE_BIN:-}" ] && [ -x "${TABOC_OPENCODE_BIN}" ]; then
    printf '%s\n' "${TABOC_OPENCODE_BIN}"
    return 0
  fi
  CANDIDATE="$(command -v opencode 2>/dev/null || true)"
  if [ -n "${CANDIDATE}" ] && [ -x "${CANDIDATE}" ]; then
    printf '%s\n' "${CANDIDATE}"
    return 0
  fi
  for CANDIDATE in /opt/homebrew/bin/opencode /usr/local/bin/opencode "${HOME}/.local/bin/opencode"; do
    if [ -x "${CANDIDATE}" ]; then
      printf '%s\n' "${CANDIDATE}"
      return 0
    fi
  done
  return 1
}

if [ "${1:-}" = "--check" ]; then
  command -v launchctl >/dev/null 2>&1 || { echo "taboc requires macOS launchctl" >&2; exit 69; }
  OPENCODE_BIN="$(resolve_opencode_bin)" || { echo "opencode not found; checked PATH, /opt/homebrew/bin, /usr/local/bin, ~/.local/bin" >&2; exit 127; }
  printf 'ready|%s|%s\n' "${OPENCODE_BIN}" "$("${OPENCODE_BIN}" --version 2>/dev/null || echo unknown)"
  exit 0
fi

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
STATUS_FILE="${STATE_DIR}/${WORKER_ID}.status"
LABEL_FILE="${STATE_DIR}/${WORKER_ID}.label"
JOURNAL="${REPO}/.taboc/journal.md"
REPO_HASH="$(printf '%s' "${REPO}" | shasum -a 256 | cut -c1-12)"
LABEL="com.taboc.${REPO_HASH}.${WORKER_ID}"
mkdir -p "${STATE_DIR}/attempts"
touch "${JOURNAL}"

if ! command -v launchctl >/dev/null 2>&1; then
  printf 'blocked|launchctl-missing|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_BLOCKED] %s | launchctl unavailable | keep task queued; do not upgrade\n' "${WORKER_ID}" >> "${JOURNAL}"
  exit 69
fi
OPENCODE_BIN="$(resolve_opencode_bin || true)"
if [ -z "${OPENCODE_BIN}" ]; then
  printf 'blocked|opencode-missing|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_BLOCKED] %s | opencode unavailable; checked PATH and Homebrew paths | keep task queued; do not upgrade\n' "${WORKER_ID}" >> "${JOURNAL}"
  exit 127
fi

if ! mkdir "${RUN_LOCK}" 2>/dev/null; then
  OLD_PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
  ACTIVE_LABEL_PID="$(launchctl list 2>/dev/null | awk -v label="${LABEL}" '$3 == label {print $1; exit}')"
  if { [ -n "${ACTIVE_LABEL_PID}" ] && kill -0 "${ACTIVE_LABEL_PID}" 2>/dev/null; } || \
     { [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null; }; then
    echo "worker run lock exists and worker is active: ${WORKER_ID}" >&2
    exit 3
  fi
  rmdir "${RUN_LOCK}" 2>/dev/null || { echo "worker run lock is not empty: ${WORKER_ID}" >&2; exit 3; }
  mkdir "${RUN_LOCK}"
fi

LOG_FILE="${STATE_DIR}/${WORKER_ID}.launcher.log"
LAUNCH_PATH="$(dirname "${OPENCODE_BIN}"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
printf 'launched|pending|pending|0\n' > "${STATUS_FILE}"
printf '%s\n' "${LABEL}" > "${LABEL_FILE}"
: > "${LOG_FILE}"

if ! launchctl submit -l "${LABEL}" -o "${LOG_FILE}" -e "${LOG_FILE}" -- \
  /usr/bin/env "TABOC_OPENCODE_BIN=${OPENCODE_BIN}" "TABOC_RUN_LOCK=${RUN_LOCK}" \
  "PATH=${LAUNCH_PATH}" "HOME=${HOME}" "TMPDIR=${TMPDIR:-/tmp}" \
  /bin/bash "${SCRIPT_DIR}/opencode-worker.sh" --repo "${REPO}" --id "${WORKER_ID}" \
  --profile "${PROFILE}" --effort "${EFFORT}" --prompt-file "${PROMPT_FILE}"; then
  rmdir "${RUN_LOCK}" 2>/dev/null || true
  printf 'blocked|launch-failed|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_BLOCKED] %s | launchctl submit failed | keep task queued; do not upgrade\n' "${WORKER_ID}" >> "${JOURNAL}"
  exit 70
fi

echo "launched ${WORKER_ID} label=${LABEL} log=${LOG_FILE}"
