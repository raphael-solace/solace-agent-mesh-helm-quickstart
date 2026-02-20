#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-rafa-demos}"
RELEASE="${RELEASE:-sam-agent-019c7013-bf70-7390-a123-f693d93b5e1c}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CHART_PATH="${CHART_PATH:-${REPO_ROOT}/charts/solace-agent-mesh-agent}"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/configs/banking-orchestrator-managed.yaml}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd helm
require_cmd kubectl

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "Config not found: ${CONFIG_PATH}" >&2
  exit 1
fi

TMP_VALUES="$(mktemp)"
cleanup() {
  rm -f "${TMP_VALUES}"
}
trap cleanup EXIT

echo "Reading current values from ${RELEASE} (${NAMESPACE})"
helm -n "${NAMESPACE}" get values "${RELEASE}" -o yaml > "${TMP_VALUES}"

echo "Applying orchestrator config: ${CONFIG_PATH}"
helm upgrade --install "${RELEASE}" "${CHART_PATH}" \
  -n "${NAMESPACE}" \
  -f "${TMP_VALUES}" \
  --set-file "config.yaml=${CONFIG_PATH}"

echo "Waiting for rollout: deployment/${RELEASE}"
kubectl -n "${NAMESPACE}" rollout status "deployment/${RELEASE}" --timeout=300s

echo "Done. Current allow_list:"
helm -n "${NAMESPACE}" get values "${RELEASE}" -o yaml \
  | sed -n '/inter_agent_communication:/,/request_timeout_seconds:/p'
