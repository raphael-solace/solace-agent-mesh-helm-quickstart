#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_NAME="${SAM_DEMO_IMAGE:-sam-enterprise-demo-runner:local}"
CONTAINER_NAME="${SAM_DEMO_CONTAINER_NAME:-sam-enterprise-demo-runner}"
KUBE_DIR="${SAM_KUBE_DIR:-${HOME}/.kube}"
MINIKUBE_DIR="${SAM_MINIKUBE_DIR:-${HOME}/.minikube}"
WAIT_SECONDS="${SAM_DEMO_WAIT_SECONDS:-180}"
BOOTSTRAP_WAIT_SECONDS="${SAM_DEMO_BOOTSTRAP_WAIT_SECONDS:-900}"
LITELLM_KEY_VALUE="${LITELLM_KEY:-${SAM_LITELLM_KEY:-}}"
SAM_VALUES_FILE_OVERRIDE="${SAM_DEMO_VALUES_FILE:-}"
HOST_UI_PORT="${SAM_HOST_UI_PORT:-8000}"
HOST_PLATFORM_PORT="${SAM_HOST_PLATFORM_PORT:-8080}"
HOST_AUTH_PORT="${SAM_HOST_AUTH_PORT:-5050}"
CONTAINER_UI_PORT="${SAM_CONTAINER_UI_PORT:-8000}"
CONTAINER_PLATFORM_PORT="${SAM_CONTAINER_PLATFORM_PORT:-8080}"
CONTAINER_AUTH_PORT="${SAM_CONTAINER_AUTH_PORT:-5050}"
PLATFORM_HEALTH_URL="${SAM_HOST_PLATFORM_URL:-http://127.0.0.1:${HOST_PLATFORM_PORT}/api/v1/platform/health}"
UI_PROJECTS_URL="${SAM_HOST_UI_URL:-http://127.0.0.1:${HOST_UI_PORT}/api/v1/projects}"
DEMO_UP_COMMAND="${SAM_DEMO_UP_CMD:-./demo up}"
DEMO_DOWN_COMMAND="${SAM_DEMO_DOWN_CMD:-./demo down}"
PORT_FORWARD_ADDRESS="${SAM_PORT_FORWARD_ADDRESS:-0.0.0.0}"
BOOTSTRAP_COMPLETE_MARKER="demo up completed; keeping container alive for access"

usage() {
  cat <<EOF
Usage: $(basename "$0") <build|up|down|logs|shell|status>

Commands:
  build   Build/update the local demo runner image
  up      Start demo in a persistent container and expose UI/API/Auth ports
  down    Stop demo container and remove it
  logs    Tail demo container logs
  shell   Open a shell in the running demo container
  status  Show container + endpoint status

Environment overrides:
  SAM_DEMO_IMAGE           (default: ${IMAGE_NAME})
  SAM_DEMO_CONTAINER_NAME  (default: ${CONTAINER_NAME})
  SAM_KUBE_DIR             (default: ~/.kube)
  SAM_MINIKUBE_DIR         (default: ~/.minikube)
  SAM_DEMO_WAIT_SECONDS    (default: ${WAIT_SECONDS})
  SAM_DEMO_BOOTSTRAP_WAIT_SECONDS
                           (default: ${BOOTSTRAP_WAIT_SECONDS})
  SAM_DEMO_VALUES_FILE     (optional in-container path for demo values file)
  SAM_HOST_UI_PORT         (default: ${HOST_UI_PORT})
  SAM_HOST_PLATFORM_PORT   (default: ${HOST_PLATFORM_PORT})
  SAM_HOST_AUTH_PORT       (default: ${HOST_AUTH_PORT})
  SAM_DEMO_UP_CMD          (default: ${DEMO_UP_COMMAND})
  SAM_DEMO_DOWN_CMD        (default: ${DEMO_DOWN_COMMAND})
  LITELLM_KEY              (optional; if unset you will be prompted on 'up')
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

build_image() {
  echo "Building ${IMAGE_NAME}"
  docker build \
    -f "${ROOT_DIR}/demos/containerized-runner/Dockerfile" \
    -t "${IMAGE_NAME}" \
    "${ROOT_DIR}"
}

container_exists() {
  docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1
}

container_running() {
  [[ "$(docker container inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)" == "true" ]]
}

print_urls() {
  cat <<EOF
Demo container is running.
UI:       http://127.0.0.1:${HOST_UI_PORT}
Platform: http://127.0.0.1:${HOST_PLATFORM_PORT}
Auth:     http://127.0.0.1:${HOST_AUTH_PORT}
EOF
}

prompt_litellm_key() {
  if [[ -n "${LITELLM_KEY_VALUE}" ]]; then
    return 0
  fi

  local value=""
  while [[ -z "${value}" ]]; do
    read -r -s -p "LiteLLM key? " value
    echo
    if [[ -z "${value}" ]]; then
      echo "LiteLLM key cannot be empty."
    fi
  done
  LITELLM_KEY_VALUE="${value}"
}

wait_endpoints_ready() {
  require_cmd curl

  local i code_platform code_ui
  for i in $(seq 1 "${WAIT_SECONDS}"); do
    if ! container_running; then
      echo "Container '${CONTAINER_NAME}' exited before endpoints became ready." >&2
      print_debug_logs
      return 1
    fi

    code_platform="$(curl -s -o /tmp/demo-container-health.out -w '%{http_code}' --max-time 4 "${PLATFORM_HEALTH_URL}" 2>/dev/null || true)"
    code_ui="$(curl -s -o /tmp/demo-container-ui.out -w '%{http_code}' --max-time 4 "${UI_PROJECTS_URL}" 2>/dev/null || true)"
    if [[ "${code_platform}" == "200" && "${code_ui}" == "200" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_bootstrap_complete() {
  local elapsed=0

  while (( elapsed < BOOTSTRAP_WAIT_SECONDS )); do
    if ! container_running; then
      echo "Container '${CONTAINER_NAME}' exited before bootstrap completed." >&2
      print_debug_logs
      return 1
    fi

    if docker logs --tail 120 "${CONTAINER_NAME}" 2>/dev/null | grep -Fq "${BOOTSTRAP_COMPLETE_MARKER}"; then
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "Demo bootstrap did not complete within ${BOOTSTRAP_WAIT_SECONDS}s." >&2
  print_debug_logs
  return 1
}

endpoints_ready_now() {
  require_cmd curl
  local code_platform code_ui
  code_platform="$(curl -s -o /tmp/demo-container-health-now.out -w '%{http_code}' --max-time 4 "${PLATFORM_HEALTH_URL}" 2>/dev/null || true)"
  code_ui="$(curl -s -o /tmp/demo-container-ui-now.out -w '%{http_code}' --max-time 4 "${UI_PROJECTS_URL}" 2>/dev/null || true)"
  [[ "${code_platform}" == "200" && "${code_ui}" == "200" ]]
}

print_debug_logs() {
  echo "----- container logs (tail 200) -----" >&2
  docker logs --tail 200 "${CONTAINER_NAME}" >&2 || true

  if container_running; then
    echo "----- in-container port-forward logs (tail 120) -----" >&2
    docker exec "${CONTAINER_NAME}" bash -lc 'test -f /tmp/sam-port-forward.log && tail -n 120 /tmp/sam-port-forward.log' >&2 || true
  fi
}

resolve_mounts() {
  local mounts=()
  mounts+=("-v" "${ROOT_DIR}:/workspace")

  if [[ -d "${KUBE_DIR}" ]]; then
    mounts+=("-v" "${KUBE_DIR}:/root/.kube:ro")
  else
    echo "Warning: kube directory not found at ${KUBE_DIR}" >&2
  fi

  if [[ -d "${MINIKUBE_DIR}" ]]; then
    mounts+=("-v" "${MINIKUBE_DIR}:/root/.minikube:ro")
  else
    echo "Warning: minikube directory not found at ${MINIKUBE_DIR}" >&2
  fi

  printf '%s\n' "${mounts[@]}"
}

up_container() {
  ensure_image_exists

  if container_running; then
    if endpoints_ready_now && docker logs --tail 120 "${CONTAINER_NAME}" 2>/dev/null | grep -Fq "${BOOTSTRAP_COMPLETE_MARKER}"; then
      echo "Container '${CONTAINER_NAME}' is already running."
      print_urls
      return 0
    fi
    echo "Container '${CONTAINER_NAME}' is running but unhealthy; recreating it." >&2
    print_debug_logs
    docker rm -f "${CONTAINER_NAME}" >/dev/null
  fi

  if container_exists; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null
  fi

  prompt_litellm_key

  local -a mount_args
  local mount_line
  while IFS= read -r mount_line; do
    mount_args+=("${mount_line}")
  done < <(resolve_mounts)

  local demo_values_file="${SAM_VALUES_FILE_OVERRIDE}"
  if [[ -z "${demo_values_file}" && -f "${ROOT_DIR}/custom-values.yaml" ]]; then
    demo_values_file="/workspace/custom-values.yaml"
  fi

  local -a env_args
  env_args+=(-e SAM_NAMESPACE="${SAM_NAMESPACE:-rafa-demos}")
  env_args+=(-e SAM_RELEASE="${SAM_RELEASE:-agent-mesh}")
  env_args+=(-e SAM_PLATFORM_URL="${SAM_CONTAINER_PLATFORM_URL:-http://127.0.0.1:${CONTAINER_PLATFORM_PORT}}")
  env_args+=(-e SAM_UI_URL="${SAM_CONTAINER_UI_URL:-http://127.0.0.1:${CONTAINER_UI_PORT}}")
  env_args+=(-e PATCH_LOCAL_KUBECONFIG="${PATCH_LOCAL_KUBECONFIG:-true}")
  env_args+=(-e HOST_HOME="${HOME}")
  env_args+=(-e SAM_PORT_FORWARD_ADDRESS="${PORT_FORWARD_ADDRESS}")
  env_args+=(-e LITELLM_KEY="${LITELLM_KEY_VALUE}")
  if [[ -n "${demo_values_file}" ]]; then
    env_args+=(-e DEMO_SAM_VALUES_FILE="${demo_values_file}")
  fi

  docker run -d \
    --name "${CONTAINER_NAME}" \
    --add-host=host.docker.internal:host-gateway \
    -p "${HOST_UI_PORT}:${CONTAINER_UI_PORT}" \
    -p "${HOST_PLATFORM_PORT}:${CONTAINER_PLATFORM_PORT}" \
    -p "${HOST_AUTH_PORT}:${CONTAINER_AUTH_PORT}" \
    "${mount_args[@]}" \
    "${env_args[@]}" \
    "${IMAGE_NAME}" \
    bash -lc "${DEMO_UP_COMMAND} && echo '${BOOTSTRAP_COMPLETE_MARKER}' && exec tail -f /dev/null" >/dev/null

  echo "Container '${CONTAINER_NAME}' started. Waiting for local URLs..."
  if ! wait_endpoints_ready; then
    echo "Endpoints did not become ready within ${WAIT_SECONDS}s." >&2
    print_debug_logs
    echo "Run: ./scripts/demo-container.sh logs" >&2
    exit 1
  fi

  echo "Local URLs are reachable. Waiting for demo bootstrap completion..."
  if ! wait_bootstrap_complete; then
    echo "Run: ./scripts/demo-container.sh logs" >&2
    exit 1
  fi

  if ! endpoints_ready_now; then
    echo "Bootstrap completed but local URLs are not reachable from host." >&2
    print_debug_logs
    echo "Run: ./scripts/demo-container.sh logs" >&2
    exit 1
  fi

  print_urls
}

down_container() {
  if ! container_exists; then
    echo "Container '${CONTAINER_NAME}' is not present."
    return 0
  fi

  if container_running; then
    docker exec "${CONTAINER_NAME}" bash -lc "${DEMO_DOWN_COMMAND}" >/dev/null 2>&1 || true
    docker stop "${CONTAINER_NAME}" >/dev/null
  fi

  docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  echo "Container '${CONTAINER_NAME}' stopped and removed."
}

logs_container() {
  if ! container_exists; then
    echo "Container '${CONTAINER_NAME}' is not present." >&2
    exit 1
  fi
  docker logs -f "${CONTAINER_NAME}"
}

shell_container() {
  if ! container_running; then
    echo "Container '${CONTAINER_NAME}' is not running." >&2
    echo "Start it first with: ./scripts/demo-container.sh up" >&2
    exit 1
  fi
  docker exec -it "${CONTAINER_NAME}" bash
}

status_container() {
  if ! container_exists; then
    echo "Container '${CONTAINER_NAME}': not present"
    exit 1
  fi

  local status
  status="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}")"
  echo "Container '${CONTAINER_NAME}': ${status}"

  if [[ "${status}" == "running" ]]; then
    print_urls
    curl -sS -o /tmp/demo-container-health-check.out -w "Platform health HTTP %{http_code}\n" --max-time 5 "${PLATFORM_HEALTH_URL}" || true
    curl -sS -o /tmp/demo-container-ui-check.out -w "UI projects HTTP %{http_code}\n" --max-time 5 "${UI_PROJECTS_URL}" || true
  fi
}

ensure_image_exists() {
  if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    build_image
  fi
}

main() {
  require_cmd docker

  local cmd="${1:-}"
  shift || true

  case "${cmd}" in
    build)
      build_image
      ;;
    up)
      up_container
      ;;
    down)
      down_container
      ;;
    logs)
      logs_container
      ;;
    shell)
      shell_container
      ;;
    status)
      status_container
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
