# Prescriptive Workflow Sample

This folder contains a working workflow configuration for Solace Agent Mesh:

- `prescriptive-ops-workflow.yaml`: workflow app configuration
- `workflow-standalone-values.yaml`: Helm values for standalone deployment

## Deploy To `rafa-demos`

```bash
NAMESPACE=rafa-demos
RELEASE=sam-prescriptive-ops-workflow

# Reuse broker + LLM settings from the running SAM platform deployment.
BROKER_URL=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.SOLACE_BROKER_URL}' | base64 -d)
BROKER_USERNAME=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.SOLACE_BROKER_USERNAME}' | base64 -d)
BROKER_PASSWORD=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.SOLACE_BROKER_PASSWORD}' | base64 -d)
BROKER_VPN=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.SOLACE_BROKER_VPN}' | base64 -d)

LLM_MODEL=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.LLM_SERVICE_GENERAL_MODEL_NAME}' | base64 -d)
LLM_ENDPOINT=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.LLM_SERVICE_ENDPOINT}' | base64 -d)
LLM_API_KEY=$(kubectl -n "$NAMESPACE" get secret agent-mesh-environment -o jsonpath='{.data.LLM_SERVICE_API_KEY}' | base64 -d)

helm upgrade --install "$RELEASE" charts/solace-agent-mesh-agent \
  -n "$NAMESPACE" \
  -f samples/workflow/workflow-standalone-values.yaml \
  --set-file config.yaml=samples/workflow/prescriptive-ops-workflow.yaml \
  --set solaceBroker.url="$BROKER_URL" \
  --set solaceBroker.username="$BROKER_USERNAME" \
  --set solaceBroker.password="$BROKER_PASSWORD" \
  --set solaceBroker.vpn="$BROKER_VPN" \
  --set llmService.generalModelName="$LLM_MODEL" \
  --set llmService.endpoint="$LLM_ENDPOINT" \
  --set llmService.apiKey="$LLM_API_KEY"
```

## Verify

```bash
kubectl -n rafa-demos get deploy sam-prescriptive-ops-workflow
kubectl -n rafa-demos get pod -l app.kubernetes.io/instance=sam-prescriptive-ops-workflow
kubectl -n rafa-demos logs deploy/sam-prescriptive-ops-workflow --tail=120
```

Healthy startup log includes:

- `S3ArtifactService initialized successfully`
- `Workflow ready: SAM Prescriptive Operations Workflow`

## Confirm It Is Published To Agent Mesh

```bash
kubectl -n rafa-demos port-forward svc/agent-mesh 18000:80
```

In a second terminal:

```bash
curl -sS http://127.0.0.1:18000/api/v1/agentCards | jq -r '.[].name'
```

Expected output includes:

- `SAM Prescriptive Operations Workflow`

## Troubleshooting

- If pod exits with `Access denied to S3 bucket`, ensure `global.persistence.namespaceId` matches:

```bash
kubectl -n rafa-demos get secret agent-mesh-seaweedfs -o jsonpath='{.metadata.labels.app\.kubernetes\.io/namespace-id}'
```

- After changing persistence-related values, restart the deployment so env vars refresh:

```bash
kubectl -n rafa-demos rollout restart deploy/sam-prescriptive-ops-workflow
```
