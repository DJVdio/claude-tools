#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTA_STATE="${TABOC_QUOTA_STATE:-${XDG_STATE_HOME:-${HOME}/.local/state}/taboc/opencode-free-quota.json}"

check_quota() {
  python3 "${SCRIPT_DIR}/quota-state.py" check --state "${QUOTA_STATE}"
}

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
  command -v python3 >/dev/null 2>&1 || { echo "taboc requires python3" >&2; exit 69; }
  QUOTA_CODE=0
  QUOTA_INFO="$(check_quota)" || QUOTA_CODE=$?
  [ "${QUOTA_CODE}" -ne 75 ] || { echo "OpenCode free pool ${QUOTA_INFO}" >&2; exit 75; }
  OPENCODE_BIN="$(resolve_opencode_bin)" || { echo "opencode not found; checked PATH, /opt/homebrew/bin, /usr/local/bin, ~/.local/bin" >&2; exit 127; }
  printf 'ready|%s|%s\n' "${OPENCODE_BIN}" "$("${OPENCODE_BIN}" --version 2>/dev/null || echo unknown)"
  exit 0
fi

REPO=""
WORKER_ID=""
PROFILE=""
EFFORT=""
PROMPT_FILE=""
RETRY=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --id) WORKER_ID="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --retry) RETRY="yes"; shift ;;
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
PID_FILE="${STATE_DIR}/${WORKER_ID}.pid"
LABEL_FILE="${STATE_DIR}/${WORKER_ID}.label"
PLIST_FILE="${STATE_DIR}/${WORKER_ID}.plist"
JOURNAL="${REPO}/.taboc/journal.md"
REPO_HASH="$(printf '%s' "${REPO}" | shasum -a 256 | cut -c1-12)"
LABEL="com.taboc.${REPO_HASH}.${WORKER_ID}"
DOMAIN="gui/$(id -u)"
mkdir -p "${STATE_DIR}/attempts"
touch "${JOURNAL}"

QUOTA_CODE=0
QUOTA_INFO="$(check_quota)" || QUOTA_CODE=$?
if [ "${QUOTA_CODE}" -eq 75 ]; then
  printf 'blocked|quota|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_QUOTA] %s | %s | reroute readonly task to gpt-5.6-luna/low\n' "${WORKER_ID}" "${QUOTA_INFO}" >> "${JOURNAL}"
  echo "OpenCode free pool ${QUOTA_INFO}" >&2
  exit 75
fi

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

if [ -z "${RETRY}" ] && { grep -Fq "[DONE] ${WORKER_ID} |" "${JOURNAL}" \
  || grep -Fq "[HANDOFF] ${WORKER_ID} →" "${JOURNAL}" \
  || grep -Fq "[DECISION] ${WORKER_ID} |" "${JOURNAL}"; }; then
  echo "worker already has a terminal journal record: ${WORKER_ID}; refusing duplicate launch" >&2
  exit 4
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
ENV_ARGS=()
for ENV_NAME in TABOC_MODELS TABOC_MAX_ATTEMPTS TABOC_ATTEMPT_TIMEOUT TABOC_ATTEMPT_HARD_TIMEOUT TABOC_STARTUP_HOLD TABOC_QUOTA_STATE TABOC_QUOTA_FALLBACK_SECONDS; do
  [ -n "${!ENV_NAME:-}" ] && ENV_ARGS+=("${ENV_NAME}=${!ENV_NAME}")
done
printf 'launched|pending|pending|0\n' > "${STATUS_FILE}"
printf '%s\n' "${LABEL}" > "${LABEL_FILE}"
: > "${LOG_FILE}"

launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
python3 "${SCRIPT_DIR}/write-launch-plist.py" --output "${PLIST_FILE}" --label "${LABEL}" --log "${LOG_FILE}" -- \
  /usr/bin/env "TABOC_OPENCODE_BIN=${OPENCODE_BIN}" "TABOC_RUN_LOCK=${RUN_LOCK}" \
  "${ENV_ARGS[@]}" \
  "PATH=${LAUNCH_PATH}" "HOME=${HOME}" "TMPDIR=${TMPDIR:-/tmp}" \
  /bin/bash "${SCRIPT_DIR}/opencode-worker.sh" --repo "${REPO}" --id "${WORKER_ID}" \
  --profile "${PROFILE}" --effort "${EFFORT}" --prompt-file "${PROMPT_FILE}"

bash "${SCRIPT_DIR}/register-assignment.sh" --repo "${REPO}" --task "${WORKER_ID}" \
  --agent "${WORKER_ID}" --pool opencode --model auto-free --effort "${EFFORT}"

if ! launchctl bootstrap "${DOMAIN}" "${PLIST_FILE}"; then
  rmdir "${RUN_LOCK}" 2>/dev/null || true
  printf 'blocked|launch-failed|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_BLOCKED] %s | launchctl bootstrap failed | keep task queued; do not upgrade\n' "${WORKER_ID}" >> "${JOURNAL}"
  exit 70
fi

echo "launched-once ${WORKER_ID} label=${LABEL} log=${LOG_FILE}"
