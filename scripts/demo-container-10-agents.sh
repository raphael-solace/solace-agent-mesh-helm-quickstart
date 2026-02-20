#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SAM_DEMO_IMAGE="${SAM_DEMO_IMAGE:-sam-demo-10-agents:local}"
export SAM_DEMO_CONTAINER_NAME="${SAM_DEMO_CONTAINER_NAME:-sam-demo-10-agents}"
export SAM_DEMO_UP_CMD="${SAM_DEMO_UP_CMD:-./demos/profiles/ten-agents/demo-up.sh}"
export SAM_DEMO_DOWN_CMD="${SAM_DEMO_DOWN_CMD:-./demos/profiles/ten-agents/demo-down.sh}"
export SAM_HOST_UI_PORT="${SAM_HOST_UI_PORT:-8100}"
export SAM_HOST_PLATFORM_PORT="${SAM_HOST_PLATFORM_PORT:-8180}"
export SAM_HOST_AUTH_PORT="${SAM_HOST_AUTH_PORT:-5150}"

exec "${SCRIPT_DIR}/demo-container.sh" "$@"
