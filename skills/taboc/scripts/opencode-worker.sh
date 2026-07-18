#!/usr/bin/env bash
set -uo pipefail

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
command -v opencode >/dev/null 2>&1 || { echo "opencode not found" >&2; exit 127; }

STATE_DIR="${REPO}/.taboc/opencode"
mkdir -p "${STATE_DIR}/attempts"
STATUS_FILE="${STATE_DIR}/${WORKER_ID}.status"
JOURNAL="${REPO}/.taboc/journal.md"

if [ "${PROFILE}" = "readonly" ]; then
  PERMISSIONS='{"*":"deny","read":"allow","glob":"allow","grep":"allow","lsp":"allow","webfetch":"allow","edit":{"*":"deny",".taboc/journal.md":"allow","**/.taboc/journal.md":"allow"}}'
else
  PERMISSIONS='{"*":"allow","question":"deny","task":"deny","external_directory":"deny","bash":{"*":"allow","git commit*":"deny","git push*":"deny","git reset*":"deny","git clean*":"deny","git checkout*":"deny","git switch*":"deny","sudo *":"deny","rm -rf *":"deny"}}'
fi

available_models() {
  opencode models opencode 2>/dev/null | awk '/^opencode\/.+-free$/ {print}'
}

supports_variant() {
  local MODEL="$1"
  local VARIANT="$2"
  opencode models opencode --verbose 2>/dev/null | awk -v target="${MODEL}" -v variant="\"${VARIANT}\"" '
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

is_retryable_failure() {
  local FILE="$1"
  rg -qi '(^|[^0-9])(402|429)([^0-9]|$)|quota|rate.?limit|usage.?limit|credit|capacity|overload|model.+(unavailable|not found|disabled)|ECONNRESET|ETIMEDOUT|ENOTFOUND|stream error|empty response|temporarily unavailable' "${FILE}"
}

MODEL=""
VARIANT=""
ATTEMPT=0
MAX_ATTEMPTS="${TABOC_MAX_ATTEMPTS:-8}"
PREVIOUS=""

while IFS= read -r MODEL; do
  [ -n "${MODEL}" ] || continue
  ATTEMPT=$((ATTEMPT + 1))
  [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ] || break
  VARIANT="$(choose_variant "${MODEL}" "${EFFORT}")"
  ATTEMPT_LOG="${STATE_DIR}/attempts/${WORKER_ID}.${ATTEMPT}.log"
  printf 'running|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
  if [ -n "${PREVIOUS}" ]; then
    printf '[MODEL_FALLBACK] %s | %s → %s:%s | infrastructure\n' "${WORKER_ID}" "${PREVIOUS}" "${MODEL}" "${VARIANT:-default}" >> "${JOURNAL}"
  fi

  COMMAND=(opencode run --dir "${REPO}" --model "${MODEL}" --format json --title "taboc-${WORKER_ID}")
  [ -n "${VARIANT}" ] && COMMAND+=(--variant "${VARIANT}")
  COMMAND+=("$(<"${PROMPT_FILE}")")

  set +e
  OPENCODE_PERMISSION="${PERMISSIONS}" OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_AUTO_SHARE=false "${COMMAND[@]}" > "${ATTEMPT_LOG}" 2>&1
  CODE=$?
  set -e

  if [ "${CODE}" -eq 0 ] && ! is_retryable_failure "${ATTEMPT_LOG}"; then
    printf 'done|%s|%s|%s\n' "${MODEL}" "${VARIANT:-default}" "${ATTEMPT}" > "${STATUS_FILE}"
    exit 0
  fi

  cleanup_owned_locks
  PREVIOUS="${MODEL}:${VARIANT:-default}"
done < <(build_candidates)

printf 'exhausted|-|-|%s\n' "${ATTEMPT}" > "${STATUS_FILE}"
printf '[MODEL_EXHAUSTED] %s | tried=%s | inspect %s/attempts/%s.*.log\n' "${WORKER_ID}" "${ATTEMPT}" "${STATE_DIR}" "${WORKER_ID}" >> "${JOURNAL}"
exit 75
