#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-rafa-demos}"
BASE_RELEASE="${BASE_RELEASE:-sam-prescriptive-ops-workflow}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CHART_PATH="${CHART_PATH:-${REPO_ROOT}/charts/solace-agent-mesh-agent}"

TMP_VALUES="$(mktemp)"
cleanup() {
  rm -f "${TMP_VALUES}"
}
trap cleanup EXIT

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required" >&2
  exit 1
fi
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

# Reuse proven runtime settings (broker, llm, image pull secret, persistence namespace)
# from an existing working sam-agent release in this namespace.
helm -n "${NAMESPACE}" get values "${BASE_RELEASE}" -o yaml > "${TMP_VALUES}"

declare -a AGENT_SPECS=(
  "sam-agent-crm-revenue:crm-revenue.yaml"
  "sam-agent-hr-people:hr-people.yaml"
  "sam-agent-eng-product:eng-product.yaml"
  "sam-agent-legal-counsel:legal-counsel.yaml"
  "sam-agent-news-strategy:news-strategy.yaml"
  "sam-agent-fin-finance:fin-finance.yaml"
  "sam-agent-ops-operations:ops-operations.yaml"
  "sam-agent-cx-customer:cx-customer.yaml"
  "sam-agent-esg-sustainability:esg-sustainability.yaml"
  "sam-agent-factory-manufacturing:factory-manufacturing.yaml"
)

for spec in "${AGENT_SPECS[@]}"; do
  release="${spec%%:*}"
  cfg_file="${SCRIPT_DIR}/configs/${spec#*:}"

  if [[ ! -f "${cfg_file}" ]]; then
    echo "missing config: ${cfg_file}" >&2
    exit 1
  fi

  echo "Deploying ${release}"
  helm upgrade --install "${release}" "${CHART_PATH}" \
    -n "${NAMESPACE}" \
    -f "${TMP_VALUES}" \
    --set "id=${release}" \
    --set "component=agent" \
    --set "deploymentMode=deployer" \
    --set "resources.sam.requests.cpu=150m" \
    --set "resources.sam.requests.memory=256Mi" \
    --set "resources.sam.limits.cpu=600m" \
    --set "resources.sam.limits.memory=768Mi" \
    --set-file "config.yaml=${cfg_file}"

done

echo "Waiting for rollout"
for spec in "${AGENT_SPECS[@]}"; do
  release="${spec%%:*}"
  kubectl -n "${NAMESPACE}" rollout status "deployment/${release}" --timeout=300s
 done

echo "\nDeployment summary"
kubectl -n "${NAMESPACE}" get deploy \
  | rg 'sam-agent-(crm|hr|eng|legal|news|fin|ops|cx|esg|factory)'
