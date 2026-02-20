#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SAM_DEMO_IMAGE="${SAM_DEMO_IMAGE:-sam-demo-banking:local}"
export SAM_DEMO_CONTAINER_NAME="${SAM_DEMO_CONTAINER_NAME:-sam-demo-banking}"
export SAM_DEMO_UP_CMD="${SAM_DEMO_UP_CMD:-./demos/profiles/banking/demo-up.sh}"
export SAM_DEMO_DOWN_CMD="${SAM_DEMO_DOWN_CMD:-./demos/profiles/banking/demo-down.sh}"
export SAM_HOST_UI_PORT="${SAM_HOST_UI_PORT:-8000}"
export SAM_HOST_PLATFORM_PORT="${SAM_HOST_PLATFORM_PORT:-8080}"
export SAM_HOST_AUTH_PORT="${SAM_HOST_AUTH_PORT:-5050}"

exec "${SCRIPT_DIR}/demo-container.sh" "$@"
