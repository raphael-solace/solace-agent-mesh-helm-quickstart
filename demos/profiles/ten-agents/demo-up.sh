#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BASE_UP_SCRIPT="${ROOT_DIR}/demos/enterprise-bootstrap/demo-up.sh"

if [[ ! -x "${BASE_UP_SCRIPT}" ]]; then
  echo "Missing executable script: ${BASE_UP_SCRIPT}" >&2
  exit 1
fi

export DEMO_AGENTS_DIR="${DEMO_AGENTS_DIR:-${SCRIPT_DIR}/agents}"
export DEMO_PROJECT_FILE="${DEMO_PROJECT_FILE:-${SCRIPT_DIR}/config/project.json}"
export DEMO_PROJECT_NAME="${DEMO_PROJECT_NAME:-Enterprise 10-Agent Demo}"

exec "${BASE_UP_SCRIPT}" "$@"
