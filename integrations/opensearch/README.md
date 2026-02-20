# OpenSearch Integration (Docker + OpenAPI)

This folder provides a local OpenSearch stack for SAM integration work:

- OpenSearch (single-node)
- OpenSearch Dashboards
- Swagger UI hosting a local OpenAPI spec

## 1. Start the stack

```bash
cd integrations/opensearch
cp -n .env.example .env
docker compose up -d
```

Endpoints:

- OpenSearch: `http://localhost:9200`
- Dashboards: `http://localhost:5601`
- OpenAPI UI: `http://localhost:8081`
- OpenAPI YAML: `http://localhost:8081/opensearch-local.openapi.yaml`

## 2. Run end-to-end integration test

```bash
./scripts/test_integration.sh
```

What this validates:

1. OpenSearch cluster is reachable and not red
2. OpenAPI spec is served by Swagger UI
3. Random BBVA records are indexed into `bbva_intel`
4. Search query returns BBVA hits

## OpenAPI Tool Count In Connector UI

Connector tools are generated from the operations in `openapi/opensearch-local.openapi.yaml` at import time.
If you only see 4 tools, your connector is still using the earlier subset spec.

After updating the spec, re-import/reload the connector using:

- `http://localhost:8081/opensearch-local.openapi.yaml`

Quick local check of operation count:

```bash
grep -c 'operationId:' openapi/opensearch-local.openapi.yaml
```

## Minikube Connector Runtime Fix

If tool execution fails with generic runtime errors in SAM, verify the connector base URL is **not** `localhost`.

From inside a Kubernetes pod, `localhost` points to the pod itself, not your host Docker OpenSearch.

Use:

- `http://host.minikube.internal:9200`

## Prompt Placeholder Gotcha

In SAM agent/system prompts, avoid endpoint placeholders like `/{index}/_search`.
`{index}` can be interpreted as a runtime context variable and fail with:

- `Context variable not found: index`

Use angle bracket notation instead:

- `/\<index\>/_search`
- `/\<index\>/_count`

For SAM in `rafa-demos`, you can verify:

```bash
kubectl -n rafa-demos exec deploy/sam-agent-019c5114-2a98-7401-9260-16788877390e -- \
  python - <<'PY'
import urllib.request
print(urllib.request.urlopen("http://host.minikube.internal:9200/_cluster/health", timeout=5).status)
PY
```

## 3. Seed BBVA data only

```bash
./scripts/seed_bbva_data.sh
```

## 4. Stop and clean up

```bash
docker compose down
```

To remove data volume as well:

```bash
docker compose down -v
```

## Notes

- The OpenAPI file is a focused local subset in the style of the OpenSearch API specification project, intended for integration testing and tooling bootstrap in this repo.
- DynamoDB integration can be layered later as a separate module and wired to SAM tools/workflows once AWS details are provided.
