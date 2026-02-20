#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BASE_DOWN_SCRIPT="${ROOT_DIR}/demos/enterprise-bootstrap/demo-down.sh"

if [[ ! -x "${BASE_DOWN_SCRIPT}" ]]; then
  echo "Missing executable script: ${BASE_DOWN_SCRIPT}" >&2
  exit 1
fi

exec "${BASE_DOWN_SCRIPT}" "$@"
