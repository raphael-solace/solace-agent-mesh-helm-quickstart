#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

AGENTS_DIR="${DEMO_AGENTS_DIR:-${SCRIPT_DIR}/agents}"
PROJECT_FILE="${DEMO_PROJECT_FILE:-${SCRIPT_DIR}/config/project.json}"
SAM_VALUES_FILE="${DEMO_SAM_VALUES_FILE:-${SCRIPT_DIR}/config/sam-values.broker-no-key.yaml}"

NAMESPACE="${SAM_NAMESPACE:-rafa-demos}"
RELEASE="${SAM_RELEASE:-agent-mesh}"
ENV_SECRET="${SAM_ENV_SECRET:-${RELEASE}-environment}"
PULL_SECRET_FILE="${SAM_PULL_SECRET_FILE:-${ROOT_DIR}/pull-secret.yaml}"
START_SCRIPT="${SAM_START_SCRIPT:-${ROOT_DIR}/scripts/sam-start.sh}"

PLATFORM_URL="${SAM_PLATFORM_URL:-http://127.0.0.1:8080}"
UI_URL="${SAM_UI_URL:-http://127.0.0.1:8000}"

INSTALL_IF_MISSING="${SAM_INSTALL_IF_MISSING:-true}"
AUTO_APPLY_PULL_SECRET="${SAM_AUTO_APPLY_PULL_SECRET:-true}"
DEPLOY_POLL_SECONDS="${SAM_DEPLOY_POLL_SECONDS:-5}"
DEPLOY_TIMEOUT_SECONDS="${SAM_DEPLOY_TIMEOUT_SECONDS:-420}"
PROJECT_NAME_OVERRIDE="${DEMO_PROJECT_NAME:-}"

LITELLM_KEY="${LITELLM_KEY:-${SAM_LITELLM_KEY:-}}"
LAST_HTTP_CODE=""
LAST_HTTP_BODY=""

usage() {
  cat <<'EOF'
Usage: demo up

Environment overrides:
  DEMO_AGENTS_DIR               (default: <bundle>/agents)
  DEMO_PROJECT_FILE             (default: <bundle>/config/project.json)
  DEMO_SAM_VALUES_FILE          (default: <bundle>/config/sam-values.broker-no-key.yaml)
  SAM_NAMESPACE                 (default: rafa-demos)
  SAM_RELEASE                   (default: agent-mesh)
  SAM_ENV_SECRET                (default: <SAM_RELEASE>-environment)
  SAM_PLATFORM_URL              (default: http://127.0.0.1:8080)
  SAM_UI_URL                    (default: http://127.0.0.1:8000)
  SAM_INSTALL_IF_MISSING        (default: true)
  SAM_AUTO_APPLY_PULL_SECRET    (default: true)
  SAM_PULL_SECRET_FILE          (default: ./pull-secret.yaml)
  SAM_DEPLOY_TIMEOUT_SECONDS    (default: 420)
  SAM_DEPLOY_POLL_SECONDS       (default: 5)
  DEMO_PROJECT_NAME             (optional: override project name from project.json)
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

json_request() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"
  local body_file code

  body_file="$(mktemp)"

  if [[ -n "${payload}" ]]; then
    code="$(curl -sS -o "${body_file}" -w '%{http_code}' -X "${method}" \
      -H 'Content-Type: application/json' \
      --data "${payload}" \
      "${url}" || true)"
  else
    code="$(curl -sS -o "${body_file}" -w '%{http_code}' -X "${method}" "${url}" || true)"
  fi

  LAST_HTTP_CODE="${code}"
  LAST_HTTP_BODY="$(cat "${body_file}")"
  rm -f "${body_file}"

  if [[ "${code}" =~ ^2 ]]; then
    printf '%s' "${LAST_HTTP_BODY}"
    return 0
  fi

  return 1
}

form_create_project() {
  local name="$1"
  local description="$2"
  local body_file code

  body_file="$(mktemp)"
  if [[ -n "${description}" ]]; then
    code="$(curl -sS -o "${body_file}" -w '%{http_code}' -X POST \
      "${UI_URL}/api/v1/projects" \
      -F "name=${name}" \
      -F "description=${description}" || true)"
  else
    code="$(curl -sS -o "${body_file}" -w '%{http_code}' -X POST \
      "${UI_URL}/api/v1/projects" \
      -F "name=${name}" || true)"
  fi

  LAST_HTTP_CODE="${code}"
  LAST_HTTP_BODY="$(cat "${body_file}")"
  rm -f "${body_file}"

  [[ "${code}" =~ ^2 ]]
}

wait_for_url() {
  local url="$1"
  local attempts="${2:-90}"
  local i code

  for i in $(seq 1 "${attempts}"); do
    code="$(curl -sS -o /tmp/sam-demo-wait.out -w '%{http_code}' --max-time 4 "${url}" || true)"
    if [[ "${code}" == "200" ]]; then
      return 0
    fi
    sleep 1
  done

  return 1
}

discover_env_secret() {
  kubectl -n "${NAMESPACE}" get secret -o json \
    | jq -r '.items[] | select(.data.LLM_SERVICE_API_KEY != null) | .metadata.name' \
    | head -n1
}

prompt_litellm_key() {
  if [[ -n "${LITELLM_KEY}" ]]; then
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
  LITELLM_KEY="${value}"
}

install_sam_if_missing() {
  if kubectl -n "${NAMESPACE}" get deployment "${RELEASE}-core" >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${INSTALL_IF_MISSING}" != "true" ]]; then
    echo "SAM release '${RELEASE}' not found in namespace '${NAMESPACE}'." >&2
    echo "Set SAM_RELEASE/SAM_NAMESPACE correctly or set SAM_INSTALL_IF_MISSING=true." >&2
    exit 1
  fi

  if [[ ! -f "${SAM_VALUES_FILE}" ]]; then
    echo "Missing bootstrap values file: ${SAM_VALUES_FILE}" >&2
    exit 1
  fi

  require_cmd helm

  echo "Installing SAM release '${RELEASE}' into namespace '${NAMESPACE}'."
  kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

  if [[ "${AUTO_APPLY_PULL_SECRET}" == "true" && -f "${PULL_SECRET_FILE}" ]]; then
    echo "Applying pull secret from ${PULL_SECRET_FILE}"
    kubectl -n "${NAMESPACE}" apply -f "${PULL_SECRET_FILE}" >/dev/null
  fi

  helm upgrade --install "${RELEASE}" "${ROOT_DIR}/charts/solace-agent-mesh" \
    -n "${NAMESPACE}" \
    --create-namespace \
    -f "${SAM_VALUES_FILE}" \
    --set-string "llmService.llmServiceApiKey=${LITELLM_KEY}"

  kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE}-core" --timeout=600s
  if kubectl -n "${NAMESPACE}" get deployment "${RELEASE}-agent-deployer" >/dev/null 2>&1; then
    kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE}-agent-deployer" --timeout=600s
  fi
}

apply_litellm_key() {
  if ! kubectl -n "${NAMESPACE}" get secret "${ENV_SECRET}" >/dev/null 2>&1; then
    local discovered
    discovered="$(discover_env_secret || true)"
    if [[ -z "${discovered}" ]]; then
      echo "Could not locate an environment secret with LLM_SERVICE_API_KEY in namespace ${NAMESPACE}." >&2
      exit 1
    fi
    ENV_SECRET="${discovered}"
  fi

  local encoded_key
  encoded_key="$(printf '%s' "${LITELLM_KEY}" | base64 | tr -d '\n')"

  local current_key
  current_key="$(kubectl -n "${NAMESPACE}" get secret "${ENV_SECRET}" -o jsonpath='{.data.LLM_SERVICE_API_KEY}' 2>/dev/null || true)"
  if [[ "${current_key}" == "${encoded_key}" ]]; then
    echo "LiteLLM key is unchanged in secret ${ENV_SECRET}; skipping rollout restart."
    return 0
  fi

  kubectl -n "${NAMESPACE}" patch secret "${ENV_SECRET}" --type merge \
    -p "{\"data\":{\"LLM_SERVICE_API_KEY\":\"${encoded_key}\"}}" >/dev/null

  for deploy in "${RELEASE}-core" "${RELEASE}-agent-deployer"; do
    if kubectl -n "${NAMESPACE}" get deployment "${deploy}" >/dev/null 2>&1; then
      echo "Restarting ${deploy} to apply new LiteLLM key"
      kubectl -n "${NAMESPACE}" rollout restart "deployment/${deploy}" >/dev/null
      kubectl -n "${NAMESPACE}" rollout status "deployment/${deploy}" --timeout=600s
    fi
  done
}

start_local_access() {
  if [[ ! -x "${START_SCRIPT}" ]]; then
    echo "Missing executable start script: ${START_SCRIPT}" >&2
    exit 1
  fi

  "${START_SCRIPT}"

  if ! wait_for_url "${PLATFORM_URL}/api/v1/platform/health" 120; then
    echo "Platform API is not reachable at ${PLATFORM_URL}/api/v1/platform/health" >&2
    exit 1
  fi
  if ! wait_for_url "${UI_URL}/api/v1/projects" 120; then
    echo "UI API is not reachable at ${UI_URL}/api/v1/projects" >&2
    exit 1
  fi
}

fetch_all_agents() {
  local page=1
  local merged='[]'
  local response data next_page

  while true; do
    if ! response="$(json_request GET "${PLATFORM_URL}/api/v1/platform/agents?pageNumber=${page}&pageSize=100")"; then
      echo "Failed to query agents: HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
      return 1
    fi

    data="$(echo "${response}" | jq -c '.data // []')"
    merged="$(jq -cn --argjson left "${merged}" --argjson right "${data}" '$left + $right')"
    next_page="$(echo "${response}" | jq -r '.meta.pagination.nextPage // empty')"

    if [[ -z "${next_page}" ]]; then
      break
    fi
    page="${next_page}"
  done

  printf '%s' "${merged}"
}

deploy_or_update_agent() {
  local agent_id="$1"
  local agent_name="$2"
  local action="$3"
  local request response deployment_id poll_response status error_msg elapsed=0

  request="$(jq -cn --arg agentId "${agent_id}" --arg action "${action}" '{agentId:$agentId, action:$action}')"
  if ! response="$(json_request POST "${PLATFORM_URL}/api/v1/platform/agentDeployments" "${request}")"; then
    if echo "${LAST_HTTP_BODY}" | jq -r '.message // ""' | grep -qi 'active deploy operation'; then
      echo "Deployment already in progress for '${agent_name}'. Skipping new ${action} request."
      return 0
    fi
    echo "Failed to submit deployment ${action} for '${agent_name}': HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
    return 1
  fi

  deployment_id="$(echo "${response}" | jq -r '.data.deploymentId // empty')"
  if [[ -z "${deployment_id}" ]]; then
    echo "No deployment id returned for '${agent_name}'."
    return 0
  fi

  while (( elapsed < DEPLOY_TIMEOUT_SECONDS )); do
    sleep "${DEPLOY_POLL_SECONDS}"
    elapsed=$((elapsed + DEPLOY_POLL_SECONDS))

    if ! poll_response="$(json_request GET "${PLATFORM_URL}/api/v1/platform/agentDeployments/${deployment_id}")"; then
      echo "Failed polling deployment ${deployment_id} for '${agent_name}': HTTP ${LAST_HTTP_CODE}" >&2
      continue
    fi

    status="$(echo "${poll_response}" | jq -r '.data.status // "unknown"')"
    case "${status}" in
      success)
        echo "Deployment ${action} succeeded for '${agent_name}'."
        return 0
        ;;
      failed)
        error_msg="$(echo "${poll_response}" | jq -r '.data.errorMessage // "unknown error"')"
        echo "Deployment ${action} failed for '${agent_name}': ${error_msg}" >&2
        return 1
        ;;
      in_progress)
        ;;
      *)
        ;;
    esac
  done

  echo "Timed out waiting for deployment ${deployment_id} for '${agent_name}'." >&2
  return 1
}

upsert_project() {
  local default_agent_id="$1"
  local project_name project_description project_prompt
  local projects_response project_id create_response update_payload

  project_name="$(jq -r '.name' "${PROJECT_FILE}")"
  project_description="$(jq -r '.description // ""' "${PROJECT_FILE}")"
  project_prompt="$(jq -r '.systemPrompt // ""' "${PROJECT_FILE}")"

  if [[ -n "${PROJECT_NAME_OVERRIDE}" ]]; then
    project_name="${PROJECT_NAME_OVERRIDE}"
  fi

  if ! projects_response="$(json_request GET "${UI_URL}/api/v1/projects")"; then
    echo "Failed to query projects: HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
    return 1
  fi

  project_id="$(
    echo "${projects_response}" \
      | jq -r --arg name "${project_name}" '.projects[]? | select(.name == $name) | .id' \
      | head -n1
  )"

  if [[ -z "${project_id}" ]]; then
    if ! form_create_project "${project_name}" "${project_description}"; then
      echo "Failed to create project '${project_name}': HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
      return 1
    fi
    create_response="${LAST_HTTP_BODY}"
    project_id="$(echo "${create_response}" | jq -r '.id // empty')"
    if [[ -z "${project_id}" ]]; then
      echo "Project create response missing id: ${create_response}" >&2
      return 1
    fi
    echo "Created project '${project_name}' (${project_id})." >&2
  else
    echo "Using existing project '${project_name}' (${project_id})." >&2
  fi

  update_payload="$(jq -cn \
    --arg name "${project_name}" \
    --arg description "${project_description}" \
    --arg systemPrompt "${project_prompt}" \
    --arg defaultAgentId "${default_agent_id}" \
    '{
      name: $name,
      description: (if $description == "" then null else $description end),
      systemPrompt: (if $systemPrompt == "" then null else $systemPrompt end),
      defaultAgentId: (if $defaultAgentId == "" then null else $defaultAgentId end)
    }'
  )"

  if ! json_request PUT "${UI_URL}/api/v1/projects/${project_id}" "${update_payload}" >/dev/null; then
    echo "Failed to update project '${project_name}': HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
    return 1
  fi

  printf '%s' "${project_id}"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi
  if [[ $# -gt 0 ]]; then
    usage
    exit 1
  fi

  require_cmd kubectl
  require_cmd curl
  require_cmd jq

  if [[ ! -d "${AGENTS_DIR}" ]]; then
    echo "Missing agents directory: ${AGENTS_DIR}" >&2
    exit 1
  fi
  if [[ ! -f "${PROJECT_FILE}" ]]; then
    echo "Missing project spec file: ${PROJECT_FILE}" >&2
    exit 1
  fi

  prompt_litellm_key
  install_sam_if_missing
  apply_litellm_key
  start_local_access

  local all_agents response data agent_name agent_id deployment_status sync_status action
  local -a created_names=() deploy_failures=() config_files=()
  local default_agent_name default_agent_id project_id
  local agent_id_map='{}'

  all_agents="$(fetch_all_agents)"
  while IFS= read -r file; do
    config_files+=("${file}")
  done < <(find "${AGENTS_DIR}" -maxdepth 1 -type f -name '*.json' | sort)

  if [[ "${#config_files[@]}" -eq 0 ]]; then
    echo "No agent config files found in ${AGENTS_DIR}" >&2
    exit 1
  fi

  for cfg in "${config_files[@]}"; do
    agent_name="$(jq -r '.name' "${cfg}")"
    agent_id="$(
      echo "${all_agents}" \
        | jq -r --arg name "${agent_name}" 'map(select(.name == $name))[0].id // empty'
    )"

    if [[ -n "${agent_id}" ]]; then
      response="$(json_request PUT "${PLATFORM_URL}/api/v1/platform/agents/${agent_id}" "$(cat "${cfg}")")" || {
        echo "Failed to update agent '${agent_name}': HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
        continue
      }
      echo "Updated agent '${agent_name}' (${agent_id})."
    else
      response="$(json_request POST "${PLATFORM_URL}/api/v1/platform/agents" "$(cat "${cfg}")")" || {
        echo "Failed to create agent '${agent_name}': HTTP ${LAST_HTTP_CODE} ${LAST_HTTP_BODY}" >&2
        continue
      }
      agent_id="$(echo "${response}" | jq -r '.data.id // empty')"
      if [[ -z "${agent_id}" ]]; then
        echo "Create response missing id for '${agent_name}': ${response}" >&2
        continue
      fi
      echo "Created agent '${agent_name}' (${agent_id})."
    fi

    data="$(echo "${response}" | jq -c '.data')"
    all_agents="$(jq -cn --argjson left "${all_agents}" --argjson right "${data}" '$left + [$right]')"
    created_names+=("${agent_name}")
    agent_id_map="$(jq -cn --argjson map "${agent_id_map}" --arg name "${agent_name}" --arg id "${agent_id}" '$map + {($name): $id}')"

    deployment_status="$(echo "${data}" | jq -r '.deploymentStatus // "not_deployed"')"
    sync_status="$(echo "${data}" | jq -r '.syncStatus // ""')"
    action=""

    case "${deployment_status}" in
      deployed)
        if [[ "${sync_status}" == "out_of_sync" || -z "${sync_status}" ]]; then
          action="update"
        fi
        ;;
      not_deployed|failed)
        action="deploy"
        ;;
      in_progress)
        echo "Agent '${agent_name}' already has an in-progress deployment; skipping new request."
        ;;
      *)
        action="deploy"
        ;;
    esac

    if [[ -n "${action}" ]]; then
      if ! deploy_or_update_agent "${agent_id}" "${agent_name}" "${action}"; then
        deploy_failures+=("${agent_name}")
      fi
    fi
  done

  default_agent_name="$(jq -r '.defaultAgentName // ""' "${PROJECT_FILE}")"
  default_agent_id=""
  if [[ -n "${default_agent_name}" ]]; then
    default_agent_id="$(echo "${agent_id_map}" | jq -r --arg name "${default_agent_name}" '.[$name] // empty')"
  fi
  if [[ -z "${default_agent_id}" && "${#created_names[@]}" -gt 0 ]]; then
    default_agent_id="$(echo "${agent_id_map}" | jq -r --arg name "${created_names[0]}" '.[$name] // empty')"
  fi

  project_id="$(upsert_project "${default_agent_id}")"

  echo
  echo "Demo bootstrap completed."
  echo "Namespace: ${NAMESPACE}"
  echo "Release:   ${RELEASE}"
  echo "UI:        ${UI_URL}"
  echo "Platform:  ${PLATFORM_URL}"
  echo "Project:   ${project_id}"
  echo "Agents processed: ${#created_names[@]}"

  if [[ "${#deploy_failures[@]}" -gt 0 ]]; then
    echo "Agents with deployment warnings:"
    for name in "${deploy_failures[@]}"; do
      echo "  - ${name}"
    done
    echo "Check deployment status: ${PLATFORM_URL}/api/v1/platform/agentDeployments?pageNumber=1&pageSize=100"
  fi
}

main "$@"
