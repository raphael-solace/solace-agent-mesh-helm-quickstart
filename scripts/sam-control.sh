#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${SAM_NAMESPACE:-rafa-demos}"
SERVICE_NAME="${SAM_SERVICE_NAME:-agent-mesh}"
MINIKUBE_PROFILE="${SAM_MINIKUBE_PROFILE:-minikube}"
PID_FILE="${SAM_PORT_FORWARD_PID_FILE:-/tmp/sam-port-forward.pid}"
LOG_FILE="${SAM_PORT_FORWARD_LOG_FILE:-/tmp/sam-port-forward.log}"
PF_ARGS=(8000:80 8080:8080 5050:5050)
RESTART_ALL_DEPLOYS="${SAM_RESTART_ALL_DEPLOYS:-false}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <start|stop|status|restart>

Commands:
  start    Start minikube, restart SAM workloads, and start port-forward
  stop     Stop port-forward and stop minikube
  status   Show minikube, SAM workloads, and local endpoint status
  restart  Equivalent to: stop then start

Environment overrides:
  SAM_NAMESPACE              (default: rafa-demos)
  SAM_SERVICE_NAME           (default: agent-mesh)
  SAM_MINIKUBE_PROFILE       (default: minikube)
  SAM_PORT_FORWARD_PID_FILE  (default: /tmp/sam-port-forward.pid)
  SAM_PORT_FORWARD_LOG_FILE  (default: /tmp/sam-port-forward.log)
  SAM_RESTART_ALL_DEPLOYS    (default: false; when true restarts every deployment)
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

port_forward_active() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8000 -sTCP:LISTEN 2>/dev/null | grep -q kubectl || return 1
    lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null | grep -q kubectl || return 1
    lsof -nP -iTCP:5050 -sTCP:LISTEN 2>/dev/null | grep -q kubectl || return 1
    return 0
  fi

  # Fallback when lsof is unavailable.
  local code
  code="$(curl -sS -o /tmp/sam-pf-probe.out -w '%{http_code}' --max-time 3 \
    "http://127.0.0.1:8080/api/v1/platform/health" || true)"
  [[ "$code" == "200" ]]
}

discover_port_forward_pid() {
  pgrep -f "kubectl -n ${NAMESPACE} port-forward svc/${SERVICE_NAME}" | head -n1 || true
}

is_cluster_reachable() {
  kubectl cluster-info >/dev/null 2>&1
}

ensure_minikube() {
  # update-context can fail when the profile is currently stopped; that is safe.
  minikube -p "$MINIKUBE_PROFILE" update-context >/dev/null 2>&1 || true
  if ! is_cluster_reachable; then
    minikube -p "$MINIKUBE_PROFILE" start
  fi
}

wait_for_rollout() {
  local target="$1"
  if [[ "$target" == deployment/* || "$target" == deploy/* ]]; then
    local desired available ready elapsed=0
    while (( elapsed < 300 )); do
      desired="$(kubectl -n "$NAMESPACE" get "$target" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
      available="$(kubectl -n "$NAMESPACE" get "$target" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
      ready="$(kubectl -n "$NAMESPACE" get "$target" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
      if [[ "${desired:-0}" == "0" || "${available:-0}" -ge "${desired:-0}" || "${ready:-0}" -ge "${desired:-0}" ]]; then
        return 0
      fi
      sleep 2
      elapsed=$((elapsed + 2))
    done
    echo "Deployment '$target' did not reach desired availability within 300s." >&2
    return 1
  fi

  kubectl -n "$NAMESPACE" rollout status "$target" --timeout=300s
}

restart_workloads() {
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$NAMESPACE' does not exist. Nothing to start." >&2
    exit 1
  fi

  # Persistence first.
  if kubectl -n "$NAMESPACE" get statefulset/agent-mesh-postgresql >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" rollout restart statefulset/agent-mesh-postgresql
    wait_for_rollout "statefulset/agent-mesh-postgresql"
  fi

  if kubectl -n "$NAMESPACE" get statefulset/agent-mesh-seaweedfs >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" rollout restart statefulset/agent-mesh-seaweedfs
    wait_for_rollout "statefulset/agent-mesh-seaweedfs"
  fi

  if [[ "$RESTART_ALL_DEPLOYS" == "true" ]]; then
    local deploy
    while IFS= read -r deploy; do
      [[ -z "$deploy" ]] && continue
      kubectl -n "$NAMESPACE" rollout restart "$deploy"
    done < <(kubectl -n "$NAMESPACE" get deploy -o name)

    while IFS= read -r deploy; do
      [[ -z "$deploy" ]] && continue
      wait_for_rollout "$deploy"
    done < <(kubectl -n "$NAMESPACE" get deploy -o name)
  else
    local core_deploy="deployment/${SERVICE_NAME}-core"
    local deployer_deploy="deployment/${SERVICE_NAME}-agent-deployer"

    if kubectl -n "$NAMESPACE" get "$deployer_deploy" >/dev/null 2>&1; then
      kubectl -n "$NAMESPACE" rollout restart "$deployer_deploy"
      wait_for_rollout "$deployer_deploy"
    fi

    if kubectl -n "$NAMESPACE" get "$core_deploy" >/dev/null 2>&1; then
      kubectl -n "$NAMESPACE" rollout restart "$core_deploy"
      wait_for_rollout "$core_deploy"
    fi
  fi
}

stop_port_forward() {
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

start_port_forward() {
  if port_forward_active; then
    local existing_pid
    existing_pid="$(discover_port_forward_pid)"
    if [[ -n "${existing_pid:-}" ]]; then
      echo "$existing_pid" >"$PID_FILE"
    fi
    return 0
  fi

  if [[ -f "$PID_FILE" ]]; then
    local current_pid
    current_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "${current_pid:-}" ]] && kill -0 "$current_pid" >/dev/null 2>&1; then
      return 0
    fi
    rm -f "$PID_FILE"
  fi

  nohup bash -c "
set -euo pipefail
trap 'exit 0' TERM INT
while true; do
  kubectl -n '$NAMESPACE' port-forward 'svc/$SERVICE_NAME' ${PF_ARGS[*]} >>'$LOG_FILE' 2>&1 || true
  echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] port-forward exited; retrying in 2s\" >>'$LOG_FILE'
  sleep 2
done
" >/dev/null 2>&1 &
  local pf_pid=$!
  echo "$pf_pid" >"$PID_FILE"
  sleep 2
  if ! kill -0 "$pf_pid" >/dev/null 2>&1; then
    echo "Port-forward failed. Check $LOG_FILE" >&2
    tail -n 40 "$LOG_FILE" >&2 || true
    exit 1
  fi
}

wait_for_local_endpoints() {
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  local attempts=20
  local i code
  for i in $(seq 1 "$attempts"); do
    code="$(curl -sS -o /tmp/sam-control-health.out -w '%{http_code}' --max-time 4 \
      "http://127.0.0.1:8080/api/v1/platform/health" || true)"
    if [[ "$code" == "200" ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Local endpoint did not become ready on http://127.0.0.1:8080 within ${attempts}s" >&2
  echo "Check port-forward log: $LOG_FILE" >&2
  return 1
}

show_status() {
  echo "Minikube:"
  minikube -p "$MINIKUBE_PROFILE" status || true
  echo
  echo "Kubectl context:"
  kubectl config current-context || true
  echo
  echo "SAM workloads ($NAMESPACE):"
  kubectl -n "$NAMESPACE" get deploy,pods || true
  echo

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      echo "Port-forward: running (pid $pid)"
    else
      if port_forward_active; then
        pid="$(discover_port_forward_pid)"
        if [[ -n "${pid:-}" ]]; then
          echo "$pid" >"$PID_FILE"
          echo "Port-forward: running (pid $pid)"
        else
          echo "Port-forward: running (pid unknown)"
        fi
      else
        echo "Port-forward: stale pid file ($PID_FILE)"
        rm -f "$PID_FILE"
      fi
    fi
  else
    if port_forward_active; then
      local pid
      pid="$(discover_port_forward_pid)"
      if [[ -n "${pid:-}" ]]; then
        echo "$pid" >"$PID_FILE"
        echo "Port-forward: running (pid $pid)"
      else
        echo "Port-forward: running (pid unknown)"
      fi
    else
      echo "Port-forward: not running"
      rm -f "$PID_FILE"
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    echo
    for url in \
      "http://127.0.0.1:8000/" \
      "http://127.0.0.1:8080/api/v1/platform/health" \
      "http://127.0.0.1:8000/api/v1/prompts/groups"
    do
      code="$(curl -sS -o /tmp/sam-control-curl.out -w '%{http_code}' --max-time 8 "$url" || true)"
      echo "$url -> $code"
    done
  fi
}

do_start() {
  require_cmd minikube
  require_cmd kubectl
  ensure_minikube
  restart_workloads
  stop_port_forward
  start_port_forward
  wait_for_local_endpoints

  echo "SAM is ready."
  echo "UI:       http://127.0.0.1:8000"
  echo "Platform: http://127.0.0.1:8080"
  echo "Auth:     http://127.0.0.1:5050"
  echo "Port-forward log: $LOG_FILE"
}

do_stop() {
  require_cmd minikube
  stop_port_forward
  minikube -p "$MINIKUBE_PROFILE" stop || true
  echo "SAM local environment stopped."
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    start)
      do_start
      ;;
    stop)
      do_stop
      ;;
    status)
      show_status
      ;;
    restart)
      do_stop
      do_start
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "${1:-}"
