#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STOP_SCRIPT="${ROOT_DIR}/scripts/sam-stop.sh"

if [[ ! -x "${STOP_SCRIPT}" ]]; then
  echo "Missing executable stop script: ${STOP_SCRIPT}" >&2
  exit 1
fi

exec "${STOP_SCRIPT}" "$@"
