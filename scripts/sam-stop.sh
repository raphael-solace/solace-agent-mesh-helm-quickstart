#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_SCRIPT="$SCRIPT_DIR/sam-control.sh"

NAMESPACE="${SAM_NAMESPACE:-rafa-demos}"
SERVICE_NAME="${SAM_SERVICE_NAME:-agent-mesh}"
PID_FILE="${SAM_PORT_FORWARD_PID_FILE:-/tmp/sam-port-forward.pid}"

FULL_STOP=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--full]

Options:
  --full    Stop local port-forward and stop minikube cluster
EOF
}

if [[ "${1:-}" == "--full" ]]; then
  FULL_STOP=true
elif [[ $# -gt 0 ]]; then
  usage
  exit 1
fi

stop_port_forward_only() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
    fi
    rm -f "$PID_FILE"
  fi

  pkill -f "kubectl -n ${NAMESPACE} port-forward svc/${SERVICE_NAME}" >/dev/null 2>&1 || true
}

main() {
  if $FULL_STOP; then
    bash "$CONTROL_SCRIPT" stop
    exit 0
  fi

  stop_port_forward_only
  echo "Stopped local SAM port-forward (cluster still running for fast restart)."
}

main
