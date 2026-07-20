#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: opencode-worker.sh --repo PATH --id ID --effort low|medium|high|max|xhigh --prompt-file PATH" >&2
  exit 2
}

REPO=""
WORKER_ID=""
EFFORT=""
PROMPT_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --id) WORKER_ID="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -d "${REPO}" ] || usage
[ -n "${WORKER_ID}" ] || usage
[ -f "${PROMPT_FILE}" ] || usage
case "${WORKER_ID}" in *[!A-Za-z0-9._-]*) usage ;; esac
case "${EFFORT}" in low|medium|high|max|xhigh) ;; *) usage ;; esac
STATE_DIR="${REPO}/.taboc/opencode"
mkdir -p "${STATE_DIR}/attempts"
STATUS_FILE="${STATE_DIR}/${WORKER_ID}.status"
JOURNAL="${REPO}/.taboc/journal.md"
touch "${JOURNAL}"
PID_FILE="${STATE_DIR}/${WORKER_ID}.pid"
RUN_LOCK="${TABOC_RUN_LOCK:-${STATE_DIR}/${WORKER_ID}.run}"
QUOTA_STATE="${TABOC_QUOTA_STATE:-${XDG_STATE_HOME:-${HOME}/.local/state}/taboc/opencode-free-quota.json}"
QUOTA_FALLBACK_SECONDS="${TABOC_QUOTA_FALLBACK_SECONDS:-86400}"

check_quota() {
  python3 "${SCRIPT_DIR}/quota-state.py" check --state "${QUOTA_STATE}"
}

QUOTA_CODE=0
QUOTA_INFO="$(check_quota)" || QUOTA_CODE=$?
if [ "${QUOTA_CODE}" -eq 75 ]; then
  printf 'blocked|quota|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_QUOTA] %s | %s | reroute readonly task to gpt-5.6-luna/low\n' "${WORKER_ID}" "${QUOTA_INFO}" >> "${JOURNAL}"
  exit 75
fi

cleanup_runtime() {
  rmdir "${RUN_LOCK}" 2>/dev/null || true
}
handle_signal() {
  local CODE="$1"
  printf 'stopped|%s|%s|%s\n' "${MODEL:--}" "${VARIANT:--}" "${ATTEMPT:-0}" > "${STATUS_FILE}"
  exit "${CODE}"
}
trap cleanup_runtime EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM HUP
printf '%s\n' "$$" > "${PID_FILE}"

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

OPENCODE_BIN="$(resolve_opencode_bin || true)"
if [ -z "${OPENCODE_BIN}" ]; then
  printf 'blocked|opencode-missing|-|0\n' > "${STATUS_FILE}"
  printf '[POOL_BLOCKED] %s | opencode unavailable inside worker | keep task queued; do not upgrade\n' "${WORKER_ID}" >> "${JOURNAL}"
  exit 127
fi

PERMISSIONS='{"*":"deny","read":"allow","glob":"allow","grep":"allow","lsp":"allow","webfetch":"allow","edit":{"*":"deny",".taboc/journal.md":"allow","**/.taboc/journal.md":"allow"}}'

catalog_has_variant() {
  local MODEL="$1"
  local VARIANT="$2"
  printf '%s\n' "${MODEL_CATALOG}" | awk -v target="${MODEL}" -v variant="\"${VARIANT}\"" '
    $0 == target {inside=1; next}
    inside && /^opencode\// {exit}
    inside && index($0, variant ":") {found=1}
    END {exit(found ? 0 : 1)}
  '
}

query_models() {
  local LOCK="${STATE_DIR}/model-query.lock"
  local OWNER=""
  local OUTPUT=""
  local WAITED=0
  while ! mkdir "${LOCK}" 2>/dev/null; do
    OWNER="$(cat "${LOCK}/owner" 2>/dev/null || true)"
    if [ -n "${OWNER}" ] && ! kill -0 "${OWNER}" 2>/dev/null; then
      rm -f "${LOCK}/owner" 2>/dev/null || true
      rmdir "${LOCK}" 2>/dev/null || true
      continue
    fi
    WAITED=$((WAITED + 1))
    [ "${WAITED}" -lt 300 ] || return 75
    sleep 0.1
  done
  printf '%s\n' "$$" > "${LOCK}/owner"
  if OUTPUT="$("${OPENCODE_BIN}" models opencode "$@" 2>/dev/null)"; then
    :
  else
    OUTPUT=""
  fi
  rm -f "${LOCK}/owner"
  rmdir "${LOCK}" 2>/dev/null || true
  printf '%s\n' "${OUTPUT}"
}

choose_variant() {
  local MODEL="$1"
  local REQUESTED="$2"
  local CANDIDATE=""
  MODEL_CATALOG="$(query_models --verbose || true)"
  if catalog_has_variant "${MODEL}" "${REQUESTED}"; then
    echo "${REQUESTED}"
    return
  fi
  for CANDIDATE in max high medium low; do
    [ "${CANDIDATE}" = "${REQUESTED}" ] && continue
    if catalog_has_variant "${MODEL}" "${CANDIDATE}"; then
      echo "${CANDIDATE}"
      return
    fi
  done
  echo ""
}

configured_model() {
  local CONFIGURED="${TABOC_MODELS:-}"
  if [ -n "${CONFIGURED}" ]; then
    printf '%s\n' "${CONFIGURED}" | tr ',' '\n' | awk 'NF {print; exit}'
    return
  fi
  echo "opencode/deepseek-v4-flash-free"
}

journal_has_since() {
  local START_LINE="$1"
  local PREFIX="$2"
  awk -v start="${START_LINE}" -v prefix="${PREFIX}" 'NR > start && index($0, prefix) == 1 {found=1; exit} END {exit(found ? 0 : 1)}' "${JOURNAL}"
}

journal_has_exact_since() {
  local START_LINE="$1"
  local RECORD="$2"
  awk -v start="${START_LINE}" -v record="${RECORD}" 'NR > start && $0 == record {found=1; exit} END {exit(found ? 0 : 1)}' "${JOURNAL}"
}

default_idle_timeout() {
  case "${EFFORT}" in
    low) echo 180 ;;
    medium) echo 300 ;;
    high) echo 450 ;;
    max|xhigh) echo 600 ;;
  esac
}

MODEL="$(configured_model)"
ATTEMPT=1
DEFAULT_ATTEMPT_TIMEOUT="$(default_idle_timeout)"
ATTEMPT_TIMEOUT="${TABOC_ATTEMPT_TIMEOUT:-${DEFAULT_ATTEMPT_TIMEOUT}}"
ATTEMPT_HARD_TIMEOUT="${TABOC_ATTEMPT_HARD_TIMEOUT:-}"
STARTUP_HOLD="${TABOC_STARTUP_HOLD:-1.5}"
case "${ATTEMPT_TIMEOUT}" in ''|*[!0-9]*) ATTEMPT_TIMEOUT="${DEFAULT_ATTEMPT_TIMEOUT}" ;; esac
[ "${ATTEMPT_TIMEOUT}" -gt 0 ] || ATTEMPT_TIMEOUT="${DEFAULT_ATTEMPT_TIMEOUT}"
case "${ATTEMPT_HARD_TIMEOUT}" in ''|*[!0-9]*) ATTEMPT_HARD_TIMEOUT=$((ATTEMPT_TIMEOUT * 3)) ;; esac
[ "${ATTEMPT_HARD_TIMEOUT}" -gt 0 ] || ATTEMPT_HARD_TIMEOUT=$((ATTEMPT_TIMEOUT * 3))

VARIANT="$(choose_variant "${MODEL}" "${EFFORT}")"
ATTEMPT_LOG="${STATE_DIR}/attempts/${WORKER_ID}.${ATTEMPT}.log"
printf 'running|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
COMMAND=("${OPENCODE_BIN}" run --dir "${REPO}" --model "${MODEL}" --format json --title "taboc-${WORKER_ID}")
[ -n "${VARIANT}" ] && COMMAND+=(--variant "${VARIANT}")
COMMAND+=("$(<"${PROMPT_FILE}")")
JOURNAL_START="$(wc -l < "${JOURNAL}" | tr -d ' ')"

set +e
OPENCODE_PERMISSION="${PERMISSIONS}" OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_AUTO_SHARE=false \
  python3 "${SCRIPT_DIR}/run-with-timeout.py" --idle-timeout "${ATTEMPT_TIMEOUT}" \
    --hard-timeout "${ATTEMPT_HARD_TIMEOUT}" --log "${ATTEMPT_LOG}" \
    --startup-lock "${STATE_DIR}/startup.lock" --startup-hold "${STARTUP_HOLD}" -- "${COMMAND[@]}"
CODE=$?
set -e
TERMINAL_RECORD="$(python3 "${SCRIPT_DIR}/extract-terminal-record.py" \
  --log "${ATTEMPT_LOG}" --worker "${WORKER_ID}" || true)"
if [ -n "${TERMINAL_RECORD}" ] && ! journal_has_exact_since "${JOURNAL_START}" "${TERMINAL_RECORD}"; then
  printf '%s\n' "${TERMINAL_RECORD}" >> "${JOURNAL}"
fi
CLASSIFICATION="$(python3 "${SCRIPT_DIR}/classify-opencode-log.py" "${ATTEMPT_LOG}")"

if journal_has_since "${JOURNAL_START}" "[HANDOFF] ${WORKER_ID} →"; then
  printf 'done|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  exit 0
fi
if journal_has_since "${JOURNAL_START}" "[DECISION] ${WORKER_ID} |"; then
  printf 'decision|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  exit 0
fi

if [ "${CLASSIFICATION}" = "quota" ]; then
  QUOTA_INFO="$(python3 "${SCRIPT_DIR}/quota-state.py" record --state "${QUOTA_STATE}" \
    --log "${ATTEMPT_LOG}" --model "${MODEL}" --fallback-seconds "${QUOTA_FALLBACK_SECONDS}")"
  printf 'blocked|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  printf '[POOL_QUOTA] %s | %s | %s | reroute to gpt-5.6-luna/low; no free-model fallback\n' \
    "${WORKER_ID}" "${MODEL}" "${QUOTA_INFO}" >> "${JOURNAL}"
  exit 75
fi
if [ "${CLASSIFICATION}" = "error" ]; then
  printf 'failed|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  printf '[WORKER_FAILED] %s | non-retryable top-level OpenCode error | inspect %s\n' "${WORKER_ID}" "${ATTEMPT_LOG}" >> "${JOURNAL}"
  exit 1
fi
if [ "${CODE}" -eq 0 ]; then
  printf 'incomplete|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  printf '[WORKER_INCOMPLETE] %s | clean exit but no terminal journal record | resume once; do not switch model automatically\n' "${WORKER_ID}" >> "${JOURNAL}"
  exit 76
fi

printf 'exhausted|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
printf '[MODEL_EXHAUSTED] %s | DeepSeek unavailable; no other free-model fallback | inspect %s/attempts/%s.*.log\n' \
  "${WORKER_ID}" "${STATE_DIR}" "${WORKER_ID}" >> "${JOURNAL}"
exit 75
