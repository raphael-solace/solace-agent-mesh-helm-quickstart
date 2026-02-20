#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-rafa-demos}"

declare -a RELEASES=(
  "sam-agent-crm-revenue"
  "sam-agent-hr-people"
  "sam-agent-eng-product"
  "sam-agent-legal-counsel"
  "sam-agent-news-strategy"
  "sam-agent-fin-finance"
  "sam-agent-ops-operations"
  "sam-agent-cx-customer"
  "sam-agent-esg-sustainability"
  "sam-agent-factory-manufacturing"
)

for release in "${RELEASES[@]}"; do
  if helm -n "${NAMESPACE}" status "${release}" >/dev/null 2>&1; then
    echo "Uninstalling ${release}"
    helm -n "${NAMESPACE}" uninstall "${release}"
  else
    echo "Skipping ${release} (not installed)"
  fi
done
