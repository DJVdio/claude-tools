#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: opencode-worker.sh --repo PATH --id ID --profile readonly|simple --effort low|medium|high|max|xhigh --prompt-file PATH" >&2
  exit 2
}

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
    *) usage ;;
  esac
done

[ -d "${REPO}" ] || usage
[ -n "${WORKER_ID}" ] || usage
[ -f "${PROMPT_FILE}" ] || usage
case "${WORKER_ID}" in *[!A-Za-z0-9._-]*) usage ;; esac
case "${PROFILE}" in readonly|simple) ;; *) usage ;; esac
case "${EFFORT}" in low|medium|high|max|xhigh) ;; *) usage ;; esac
STATE_DIR="${REPO}/.taboc/opencode"
mkdir -p "${STATE_DIR}/attempts"
STATUS_FILE="${STATE_DIR}/${WORKER_ID}.status"
JOURNAL="${REPO}/.taboc/journal.md"
PID_FILE="${STATE_DIR}/${WORKER_ID}.pid"
RUN_LOCK="${TABOC_RUN_LOCK:-${STATE_DIR}/${WORKER_ID}.run}"

cleanup_runtime() {
  rmdir "${RUN_LOCK}" 2>/dev/null || true
}
trap cleanup_runtime EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
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

if [ "${PROFILE}" = "readonly" ]; then
  PERMISSIONS='{"*":"deny","read":"allow","glob":"allow","grep":"allow","lsp":"allow","webfetch":"allow","edit":{"*":"deny",".taboc/journal.md":"allow","**/.taboc/journal.md":"allow"}}'
else
  PERMISSIONS='{"*":"allow","question":"deny","task":"deny","external_directory":"deny","bash":{"*":"allow","git commit*":"deny","git push*":"deny","git reset*":"deny","git clean*":"deny","git checkout*":"deny","git switch*":"deny","sudo *":"deny","rm -rf *":"deny"}}'
fi

available_models() {
  "${OPENCODE_BIN}" models opencode 2>/dev/null | awk '/^opencode\/.+-free$/ {print}'
}

supports_variant() {
  local MODEL="$1"
  local VARIANT="$2"
  "${OPENCODE_BIN}" models opencode --verbose 2>/dev/null | awk -v target="${MODEL}" -v variant="\"${VARIANT}\"" '
    $0 == target {inside=1; next}
    inside && /^opencode\// {exit}
    inside && index($0, variant ":") {found=1}
    END {exit(found ? 0 : 1)}
  '
}

choose_variant() {
  local MODEL="$1"
  local REQUESTED="$2"
  local CANDIDATE=""
  if supports_variant "${MODEL}" "${REQUESTED}"; then
    echo "${REQUESTED}"
    return
  fi
  for CANDIDATE in max high medium low; do
    if supports_variant "${MODEL}" "${CANDIDATE}"; then
      echo "${CANDIDATE}"
      return
    fi
  done
  echo ""
}

build_candidates() {
  local FOUND=""
  local MODEL=""
  local CONFIGURED="${TABOC_MODELS:-}"
  local DEFAULTS="opencode/deepseek-v4-flash-free opencode/nemotron-3-ultra-free opencode/mimo-v2.5-free opencode/north-mini-code-free opencode/hy3-free"
  if [ -n "${CONFIGURED}" ]; then
    printf '%s\n' "${CONFIGURED}" | tr ',' '\n'
    return
  fi
  FOUND="$(available_models)"
  for MODEL in ${DEFAULTS}; do
    printf '%s\n' "${FOUND}" | grep -Fxq "${MODEL}" && echo "${MODEL}"
  done
  printf '%s\n' "${FOUND}" | while IFS= read -r MODEL; do
    printf '%s\n' "${DEFAULTS}" | tr ' ' '\n' | grep -Fxq "${MODEL}" || echo "${MODEL}"
  done
}

cleanup_owned_locks() {
  local LOCK=""
  local OWNER=""
  [ -d "${REPO}/.taboc/locks" ] || return
  for LOCK in "${REPO}"/.taboc/locks/*; do
    [ -d "${LOCK}" ] || continue
    OWNER="$(awk 'NR==1 {print $1}' "${LOCK}/meta" 2>/dev/null || true)"
    if [ "${OWNER}" = "${WORKER_ID}" ]; then
      rm -rf "${LOCK}"
    fi
  done
}

journal_has_since() {
  local START_LINE="$1"
  local PREFIX="$2"
  awk -v start="${START_LINE}" -v prefix="${PREFIX}" 'NR > start && index($0, prefix) == 1 {found=1; exit} END {exit(found ? 0 : 1)}' "${JOURNAL}"
}

MODEL=""
VARIANT=""
ATTEMPT=0
MAX_ATTEMPTS="${TABOC_MAX_ATTEMPTS:-8}"
PREVIOUS=""
LAST_MODEL="-"
LAST_VARIANT="-"

while IFS= read -r MODEL; do
  [ -n "${MODEL}" ] || continue
  ATTEMPT=$((ATTEMPT + 1))
  [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ] || break
  VARIANT="$(choose_variant "${MODEL}" "${EFFORT}")"
  LAST_MODEL="${MODEL}"
  LAST_VARIANT="${VARIANT:-default}"
  ATTEMPT_LOG="${STATE_DIR}/attempts/${WORKER_ID}.${ATTEMPT}.log"
  printf 'running|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  if [ -n "${PREVIOUS}" ]; then
    printf '[MODEL_FALLBACK] %s | %s → %s:%s | infrastructure\n' "${WORKER_ID}" "${PREVIOUS}" "${MODEL}" "${VARIANT:-default}" >> "${JOURNAL}"
  fi

  COMMAND=("${OPENCODE_BIN}" run --dir "${REPO}" --model "${MODEL}" --format json --title "taboc-${WORKER_ID}")
  [ -n "${VARIANT}" ] && COMMAND+=(--variant "${VARIANT}")
  COMMAND+=("$(<"${PROMPT_FILE}")")
  JOURNAL_START="$(wc -l < "${JOURNAL}" | tr -d ' ')"

  set +e
  OPENCODE_PERMISSION="${PERMISSIONS}" OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_AUTO_SHARE=false "${COMMAND[@]}" > "${ATTEMPT_LOG}" 2>&1
  CODE=$?
  set -e
  CLASSIFICATION="$(python3 "${SCRIPT_DIR}/classify-opencode-log.py" "${ATTEMPT_LOG}")"

  if { [ "${PROFILE}" = "readonly" ] && journal_has_since "${JOURNAL_START}" "[HANDOFF] ${WORKER_ID} →"; } \
    || { [ "${PROFILE}" = "simple" ] && journal_has_since "${JOURNAL_START}" "[DONE] ${WORKER_ID} |"; }; then
    printf 'done|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
    exit 0
  fi

  if journal_has_since "${JOURNAL_START}" "[DECISION] ${WORKER_ID} |"; then
    printf 'decision|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
    exit 0
  fi

  if [ "${CLASSIFICATION}" = "error" ]; then
    cleanup_owned_locks
    printf 'failed|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
    printf '[WORKER_FAILED] %s | non-retryable top-level OpenCode error | inspect %s\n' "${WORKER_ID}" "${ATTEMPT_LOG}" >> "${JOURNAL}"
    exit 1
  fi

  if [ "${CODE}" -eq 0 ] && [ "${CLASSIFICATION}" = "clean" ]; then
    cleanup_owned_locks
    printf 'incomplete|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
    printf '[WORKER_INCOMPLETE] %s | clean exit but no terminal journal record | resume once; do not switch model automatically\n' "${WORKER_ID}" >> "${JOURNAL}"
    exit 76
  fi

  cleanup_owned_locks
  PREVIOUS="${MODEL}:${VARIANT:-default}"
done < <(build_candidates)

printf 'exhausted|%s|%s|%s\n' "${LAST_MODEL}" "${LAST_VARIANT}" "${ATTEMPT}" > "${STATUS_FILE}"
printf '[MODEL_EXHAUSTED] %s | tried=%s | inspect %s/attempts/%s.*.log\n' "${WORKER_ID}" "${ATTEMPT}" "${STATE_DIR}" "${WORKER_ID}" >> "${JOURNAL}"
exit 75
