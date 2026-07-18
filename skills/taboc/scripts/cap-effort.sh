#!/usr/bin/env bash
set -euo pipefail

REQUESTED="${1:-}"
CEILING="${2:-}"

rank() {
  case "$1" in
    low) echo 1 ;;
    medium) echo 2 ;;
    high) echo 3 ;;
    max) echo 4 ;;
    xhigh) echo 5 ;;
    *) return 1 ;;
  esac
}

REQUESTED_RANK="$(rank "${REQUESTED}")" || { echo "invalid requested effort: ${REQUESTED}" >&2; exit 2; }
CEILING_RANK="$(rank "${CEILING}")" || { echo "invalid effort ceiling: ${CEILING}" >&2; exit 2; }

if [ "${REQUESTED_RANK}" -le "${CEILING_RANK}" ]; then
  echo "${REQUESTED}"
else
  echo "${CEILING}"
fi
