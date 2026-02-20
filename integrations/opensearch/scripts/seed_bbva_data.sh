#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
INDEX_NAME="${INDEX_NAME:-bbva_intel}"
DOC_COUNT="${DOC_COUNT:-20}"

"${SCRIPT_DIR}/wait_for_opensearch.sh" "${OPENSEARCH_URL}"

create_payload='{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "properties": {
      "bank": {"type": "keyword"},
      "record_id": {"type": "keyword"},
      "region": {"type": "keyword"},
      "record_type": {"type": "keyword"},
      "theme": {"type": "text"},
      "sentiment": {"type": "keyword"},
      "confidence": {"type": "integer"},
      "event_date": {"type": "date"},
      "summary": {"type": "text"},
      "source": {"type": "keyword"}
    }
  }
}'

create_tmp="$(mktemp)"
create_status="$(curl -sS -o "${create_tmp}" -w "%{http_code}" -X PUT "${OPENSEARCH_URL}/${INDEX_NAME}" -H 'Content-Type: application/json' -d "${create_payload}")"

if [[ "${create_status}" == "200" || "${create_status}" == "201" ]]; then
  echo "Created index '${INDEX_NAME}'."
elif [[ "${create_status}" == "400" ]] && jq -e '.error.type == "resource_already_exists_exception"' "${create_tmp}" >/dev/null 2>&1; then
  echo "Index '${INDEX_NAME}' already exists. Reusing it."
else
  echo "Failed to create index '${INDEX_NAME}'. Response:" >&2
  cat "${create_tmp}" >&2
  rm -f "${create_tmp}"
  exit 1
fi
rm -f "${create_tmp}"

regions=("Spain" "Mexico" "Turkey" "Argentina" "Peru" "Colombia")
record_types=("market_note" "risk_alert" "customer_feedback" "analyst_observation" "news_digest")
themes=(
  "digital banking growth"
  "SME lending momentum"
  "fraud detection improvements"
  "mobile payments adoption"
  "mortgage portfolio review"
  "green financing pipeline"
  "cross-border payments"
  "AI advisory rollout"
)
sentiments=("positive" "neutral" "watchlist")
sources=("internal_lab" "field_team" "market_feed" "analyst_desk")

bulk_file="$(mktemp)"

for i in $(seq 1 "${DOC_COUNT}"); do
  region="${regions[$((RANDOM % ${#regions[@]}))]}"
  record_type="${record_types[$((RANDOM % ${#record_types[@]}))]}"
  theme="${themes[$((RANDOM % ${#themes[@]}))]}"
  sentiment="${sentiments[$((RANDOM % ${#sentiments[@]}))]}"
  source="${sources[$((RANDOM % ${#sources[@]}))]}"
  confidence="$((55 + RANDOM % 45))"
  day=$(printf "%02d" $(((i % 27) + 1)))
  minute=$(printf "%02d" $(((i * 7) % 60)))
  timestamp="2026-02-${day}T10:${minute}:00Z"
  record_id="bbva-${i}-$((RANDOM % 100000))"

  summary="BBVA ${theme} update in ${region}. Signal=${sentiment}; confidence=${confidence}."

  printf '{"index":{"_index":"%s"}}\n' "${INDEX_NAME}" >> "${bulk_file}"
  jq -nc \
    --arg bank "BBVA" \
    --arg record_id "${record_id}" \
    --arg region "${region}" \
    --arg record_type "${record_type}" \
    --arg theme "${theme}" \
    --arg sentiment "${sentiment}" \
    --arg event_date "${timestamp}" \
    --arg summary "${summary}" \
    --arg source "${source}" \
    --argjson confidence "${confidence}" \
    '{bank: $bank, record_id: $record_id, region: $region, record_type: $record_type, theme: $theme, sentiment: $sentiment, confidence: $confidence, event_date: $event_date, summary: $summary, source: $source}' >> "${bulk_file}"
  printf '\n' >> "${bulk_file}"
done

bulk_response_file="$(mktemp)"
curl -fsS -X POST "${OPENSEARCH_URL}/_bulk?refresh=true" \
  -H 'Content-Type: application/x-ndjson' \
  --data-binary @"${bulk_file}" > "${bulk_response_file}"

if [[ "$(jq -r '.errors' "${bulk_response_file}")" != "false" ]]; then
  echo "Bulk indexing returned errors:" >&2
  jq '.items[] | select(.index.error != null)' "${bulk_response_file}" >&2
  rm -f "${bulk_file}" "${bulk_response_file}"
  exit 1
fi

indexed_count="$(jq '.items | length' "${bulk_response_file}")"
echo "Indexed ${indexed_count} BBVA records into '${INDEX_NAME}'."

rm -f "${bulk_file}" "${bulk_response_file}"
