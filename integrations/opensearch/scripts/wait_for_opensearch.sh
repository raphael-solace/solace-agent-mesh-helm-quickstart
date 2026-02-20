#!/usr/bin/env bash
set -euo pipefail

OPENSEARCH_URL="${1:-${OPENSEARCH_URL:-http://localhost:9200}}"
TIMEOUT_SECONDS="${OPENSEARCH_WAIT_TIMEOUT:-180}"
SLEEP_SECONDS=2

end_time=$((SECONDS + TIMEOUT_SECONDS))

echo "Waiting for OpenSearch at ${OPENSEARCH_URL} (timeout: ${TIMEOUT_SECONDS}s)..."

while (( SECONDS < end_time )); do
  if curl -fsS "${OPENSEARCH_URL}/_cluster/health" >/dev/null 2>&1; then
    echo "OpenSearch is reachable."
    exit 0
  fi
  sleep "${SLEEP_SECONDS}"
done

echo "Timed out waiting for OpenSearch at ${OPENSEARCH_URL}" >&2
exit 1
