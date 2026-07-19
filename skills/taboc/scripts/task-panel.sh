#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTA_STATE="${TABOC_QUOTA_STATE:-${XDG_STATE_HOME:-${HOME}/.local/state}/taboc/opencode-free-quota.json}"
QUOTA_CODE=0
QUOTA_INFO="$(python3 "${SCRIPT_DIR}/quota-state.py" check --state "${QUOTA_STATE}")" || QUOTA_CODE=$?
if [ "${QUOTA_CODE}" -eq 75 ]; then
  printf 'OpenCode Pool | %s\n\n' "${QUOTA_INFO}"
fi
exec python3 "${SCRIPT_DIR}/task-panel.py" "$@"
