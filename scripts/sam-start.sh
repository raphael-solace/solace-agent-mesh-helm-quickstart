#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_SCRIPT="$SCRIPT_DIR/sam-control.sh"

NAMESPACE="${SAM_NAMESPACE:-rafa-demos}"
SERVICE_NAME="${SAM_SERVICE_NAME:-agent-mesh}"
MINIKUBE_PROFILE="${SAM_MINIKUBE_PROFILE:-minikube}"
PID_FILE="${SAM_PORT_FORWARD_PID_FILE:-/tmp/sam-port-forward.pid}"
LOG_FILE="${SAM_PORT_FORWARD_LOG_FILE:-/tmp/sam-port-forward.log}"
PF_ARGS=(8000:80 8080:8080 5050:5050)
PORT_FORWARD_ADDRESS="${SAM_PORT_FORWARD_ADDRESS:-127.0.0.1}"
CORE_DEPLOYMENT="${SAM_CORE_DEPLOYMENT:-${SERVICE_NAME}-core}"
ENV_SECRET_NAME="${SAM_ENV_SECRET_NAME:-${SERVICE_NAME}-environment}"
AUTO_FIX_LOCAL_CORS="${SAM_AUTO_FIX_LOCAL_CORS:-true}"
LOCAL_CORS_REGEX="${SAM_LOCAL_CORS_REGEX:-https?://(localhost|127\\.0\\.0\\.1)(:\\d+)?}"
PLATFORM_HEALTH_URL="http://127.0.0.1:8080/api/v1/platform/health"
PLATFORM_AGENTS_URL="http://127.0.0.1:8080/api/v1/platform/agents?pageNumber=1&pageSize=1"
UI_PROMPTS_URL="http://127.0.0.1:8000/api/v1/prompts/groups"
LOCAL_UI_ORIGIN="http://127.0.0.1:8000"

FORCE_FULL_START=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force]

Options:
  --force   Always run full recovery start via sam-control.sh
EOF
}

if [[ "${1:-}" == "--force" ]]; then
  FORCE_FULL_START=true
elif [[ $# -gt 0 ]]; then
  usage
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

http_ok() {
  local url="$1"
  local code
  code="$(curl -sS -o /tmp/sam-start-curl.out -w '%{http_code}' --max-time 5 "$url" || true)"
  [[ "$code" == "200" ]]
}

agents_api_ready() {
  local code
  code="$(curl -sS -o /tmp/sam-start-agents.out -w '%{http_code}' --max-time 5 "$PLATFORM_AGENTS_URL" || true)"
  [[ "$code" == "200" ]] || return 1
  grep -q '"data"' /tmp/sam-start-agents.out
}

cors_allows_local_ui_origin() {
  curl -sS -D /tmp/sam-start-cors.headers \
    -o /tmp/sam-start-cors.body \
    --max-time 5 \
    -H "Origin: $LOCAL_UI_ORIGIN" \
    "$PLATFORM_AGENTS_URL" >/dev/null || return 1

  tr -d '\r' </tmp/sam-start-cors.headers | awk -v want="$LOCAL_UI_ORIGIN" '
    tolower($0) ~ /^access-control-allow-origin:/ {
      v=$0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (v==want) ok=1
    }
    END { exit(ok ? 0 : 1) }
  '
}

local_fetch_path_ready() {
  http_ok "$PLATFORM_HEALTH_URL" &&
    http_ok "$UI_PROMPTS_URL" &&
    agents_api_ready &&
    cors_allows_local_ui_origin
}

port_forward_active() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8000 -sTCP:LISTEN 2>/dev/null | grep -q kubectl || return 1
    lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null | grep -q kubectl || return 1
    lsof -nP -iTCP:5050 -sTCP:LISTEN 2>/dev/null | grep -q kubectl || return 1
    return 0
  fi

  http_ok "$PLATFORM_HEALTH_URL"
}

discover_port_forward_pid() {
  pgrep -f "kubectl -n ${NAMESPACE} port-forward svc/${SERVICE_NAME}" | head -n1 || true
}

cluster_reachable() {
  kubectl cluster-info >/dev/null 2>&1
}

ensure_minikube() {
  minikube -p "$MINIKUBE_PROFILE" update-context >/dev/null 2>&1 || true
  if ! cluster_reachable; then
    minikube -p "$MINIKUBE_PROFILE" start
  fi
}

ensure_local_cors_policy() {
  if [[ "$AUTO_FIX_LOCAL_CORS" != "true" ]]; then
    return 0
  fi

  if ! kubectl -n "$NAMESPACE" get secret "$ENV_SECRET_NAME" >/dev/null 2>&1; then
    return 0
  fi

  local current_b64 desired_b64
  current_b64="$(kubectl -n "$NAMESPACE" get secret "$ENV_SECRET_NAME" -o jsonpath='{.data.CORS_ALLOWED_ORIGIN_REGEX}' 2>/dev/null || true)"
  desired_b64="$(printf '%s' "$LOCAL_CORS_REGEX" | base64 | tr -d '\n')"

  if [[ "${current_b64:-}" == "$desired_b64" ]]; then
    return 0
  fi

  echo "Applying local CORS regex for SAM UI fetch stability."
  kubectl -n "$NAMESPACE" patch secret "$ENV_SECRET_NAME" --type merge \
    -p "{\"data\":{\"CORS_ALLOWED_ORIGIN_REGEX\":\"$desired_b64\"}}" >/dev/null

  if kubectl -n "$NAMESPACE" get deploy "$CORE_DEPLOYMENT" >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" rollout restart "deploy/$CORE_DEPLOYMENT" >/dev/null
    kubectl -n "$NAMESPACE" rollout status "deploy/$CORE_DEPLOYMENT" --timeout=300s
  fi
}

workloads_ready() {
  local target desired available ready

  for target in "${SERVICE_NAME}-core" "${SERVICE_NAME}-agent-deployer"; do
    if ! kubectl -n "$NAMESPACE" get deploy "$target" >/dev/null 2>&1; then
      continue
    fi
    desired="$(kubectl -n "$NAMESPACE" get deploy "$target" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
    available="$(kubectl -n "$NAMESPACE" get deploy "$target" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
    ready="$(kubectl -n "$NAMESPACE" get deploy "$target" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    [[ "${desired:-0}" == "0" ]] && continue
    [[ "${available:-0}" -ge "${desired:-0}" ]] || [[ "${ready:-0}" -ge "${desired:-0}" ]] || return 1
  done

  for target in "${SERVICE_NAME}-postgresql" "${SERVICE_NAME}-seaweedfs"; do
    if ! kubectl -n "$NAMESPACE" get statefulset "$target" >/dev/null 2>&1; then
      continue
    fi
    desired="$(kubectl -n "$NAMESPACE" get statefulset "$target" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
    ready="$(kubectl -n "$NAMESPACE" get statefulset "$target" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    [[ "${desired:-0}" == "0" ]] && continue
    [[ "${ready:-0}" -ge "${desired:-0}" ]] || return 1
  done

  return 0
}

stop_existing_port_forward() {
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

start_port_forward_once() {
  if port_forward_active; then
    local existing_pid
    existing_pid="$(discover_port_forward_pid)"
    if [[ -n "${existing_pid:-}" ]]; then
      echo "$existing_pid" >"$PID_FILE"
    fi
    return 0
  fi

  stop_existing_port_forward

  nohup bash -c "
set -euo pipefail
trap 'exit 0' TERM INT
while true; do
  kubectl -n '$NAMESPACE' port-forward --address '$PORT_FORWARD_ADDRESS' 'svc/$SERVICE_NAME' ${PF_ARGS[*]} >>'$LOG_FILE' 2>&1 || true
  echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] port-forward exited; retrying in 2s\" >>'$LOG_FILE'
  sleep 2
done
" >/dev/null 2>&1 &

  local pf_pid=$!
  echo "$pf_pid" >"$PID_FILE"
  sleep 2

  if ! kill -0 "$pf_pid" >/dev/null 2>&1; then
    echo "Failed to start port-forward. Check $LOG_FILE" >&2
    tail -n 40 "$LOG_FILE" >&2 || true
    exit 1
  fi
}

wait_local_endpoints() {
  local attempts=45
  local i
  for i in $(seq 1 "$attempts"); do
    if local_fetch_path_ready; then
      return 0
    fi
    sleep 1
  done

  echo "SAM local APIs are not fetch-ready in ${attempts}s. Check $LOG_FILE" >&2
  echo "Tip: open exactly $LOCAL_UI_ORIGIN (avoid random minikube service ports)." >&2
  return 1
}

print_urls() {
  cat <<EOF
SAM is ready.
UI:       http://127.0.0.1:8000
Platform: http://127.0.0.1:8080
Auth:     http://127.0.0.1:5050
EOF
}

main() {
  require_cmd minikube
  require_cmd kubectl
  require_cmd curl

  ensure_minikube

  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' does not exist. Deploy SAM first." >&2
    exit 1
  fi

  ensure_local_cors_policy

  if ! $FORCE_FULL_START && \
    port_forward_active && \
    local_fetch_path_ready; then
    echo "SAM is already reachable; skipping restart."
    print_urls
    exit 0
  fi

  if $FORCE_FULL_START; then
    bash "$CONTROL_SCRIPT" start
    exit 0
  fi

  if workloads_ready; then
    echo "Cluster workloads are healthy; starting local port-forward only."
    start_port_forward_once
    if ! wait_local_endpoints; then
      echo "Quick start did not reach stable fetch path; running full recovery start."
      bash "$CONTROL_SCRIPT" start
      if ! wait_local_endpoints; then
        echo "SAM started, but agent fetch path still fails. Verify CORS and use $LOCAL_UI_ORIGIN." >&2
        exit 1
      fi
    fi
    print_urls
    exit 0
  fi

  echo "Workloads are not fully healthy; running full recovery start."
  bash "$CONTROL_SCRIPT" start
  if ! wait_local_endpoints; then
    echo "SAM recovered, but agent fetch path still fails. Verify CORS and use $LOCAL_UI_ORIGIN." >&2
    exit 1
  fi
  print_urls
}

main
