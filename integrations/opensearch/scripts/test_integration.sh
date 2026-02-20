#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
OPENAPI_UI_URL="${OPENAPI_UI_URL:-http://localhost:8081}"
INDEX_NAME="${INDEX_NAME:-bbva_intel}"

"${SCRIPT_DIR}/wait_for_opensearch.sh" "${OPENSEARCH_URL}"
"${SCRIPT_DIR}/seed_bbva_data.sh"

cluster_status="$(curl -fsS "${OPENSEARCH_URL}/_cluster/health" | jq -r '.status')"
if [[ "${cluster_status}" == "red" ]]; then
  echo "Cluster health is RED. Failing integration test." >&2
  exit 1
fi
echo "Cluster health status: ${cluster_status}"

openapi_spec="$(curl -fsS "${OPENAPI_UI_URL}/opensearch-local.openapi.yaml")"
if ! grep -q '/_msearch:' <<<"${openapi_spec}" || ! grep -q '/_cluster/health:' <<<"${openapi_spec}"; then
  echo "OpenAPI UI/spec validation failed." >&2
  exit 1
fi
echo "OpenAPI spec endpoint is reachable: ${OPENAPI_UI_URL}/opensearch-local.openapi.yaml"

search_payload='{
  "size": 5,
  "query": {
    "term": {"bank": "BBVA"}
  },
  "sort": [{"event_date": {"order": "desc"}}]
}'

search_response="$(curl -fsS -X POST "${OPENSEARCH_URL}/${INDEX_NAME}/_search" -H 'Content-Type: application/json' -d "${search_payload}")"

hits="$(jq -r '.hits.total.value // .hits.total // 0' <<<"${search_response}")"
if [[ "${hits}" -lt 1 ]]; then
  echo "Expected at least one BBVA search hit but got ${hits}." >&2
  exit 1
fi

echo "Search returned ${hits} matching BBVA records. Sample results:"
jq -r '.hits.hits[] | [."_source".record_id, ."_source".theme, ."_source".region, ."_source".sentiment] | @tsv' <<<"${search_response}" | head -n 5

echo "Integration test passed."
