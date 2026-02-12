---
sidebar_position: 2
title: Local Minikube Runbook
---

# Local Minikube Runbook (Private Registry + Namespace)

This runbook documents a working local setup for this repository using:

- Namespace: `rafa-demos`
- Image pull secret manifest: `pull-secret.yaml`
- Values file: `custom-values.yaml`
- Local chart path: `charts/solace-agent-mesh`

It is intended for local development on a single-node Minikube cluster.

## 1. Prerequisites

- Minikube cluster running
- `kubectl` configured to target Minikube
- Helm 3+
- Local files present in repo root:
  - `custom-values.yaml`
  - `pull-secret.yaml`

Verify context:

```bash
kubectl config current-context
```

## 2. Create Namespace and Apply Pull Secret

The pull secret **must be created in the same namespace** as the Helm release.

```bash
kubectl create namespace rafa-demos --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n rafa-demos -f pull-secret.yaml
```

Verify:

```bash
kubectl get secret gcr-reg-secret -n rafa-demos -o jsonpath='{.type}'; echo
# expected: kubernetes.io/dockerconfigjson
```

## 3. Install or Upgrade SAM

```bash
helm upgrade --install agent-mesh charts/solace-agent-mesh \
  -f custom-values.yaml \
  -n rafa-demos --create-namespace
```

Wait for rollout:

```bash
kubectl rollout status deployment/agent-mesh-core -n rafa-demos --timeout=300s
kubectl rollout status deployment/agent-mesh-agent-deployer -n rafa-demos --timeout=300s
kubectl rollout status statefulset/agent-mesh-postgresql -n rafa-demos --timeout=300s
kubectl rollout status statefulset/agent-mesh-seaweedfs -n rafa-demos --timeout=300s
```

Check pods:

```bash
kubectl get pods -n rafa-demos -l app.kubernetes.io/instance=agent-mesh
```

## 4. Access SAM Locally (Important Port Mapping)

For local browser access, forward all three ports:

```bash
kubectl -n rafa-demos port-forward svc/agent-mesh 8000:80 8080:8080 5050:5050
```

Use:

- Web UI: `http://127.0.0.1:8000`
- Platform API: `http://127.0.0.1:8080`
- Auth endpoint: `http://127.0.0.1:5050`

Why this mapping:

- Service `80` routes to container port `8000` (Web UI/backend gateway)
- Service `8080` routes to container port `8001` (Platform API)
- Service `5050` routes to auth service

If you only forward `8000:80`, platform calls from the UI can fail with "Failed to fetch".

## 5. Local URL Overrides Required in `custom-values.yaml`

For localhost workflows, set:

```yaml
sam:
  dnsName: "127.0.0.1"
  frontendServerUrl: "http://127.0.0.1:8000"
  platformServiceUrl: "http://127.0.0.1:8080"
```

Validate effective runtime config:

```bash
kubectl get secret -n rafa-demos agent-mesh-environment -o json | \
  jq -r '.data | to_entries[] |
  select(.key|test("FRONTEND_SERVER_URL|PLATFORM_SERVICE_URL|EXTERNAL_AUTH_SERVICE_URL|FRONTEND_REDIRECT_URL")) |
  "\(.key)=\(.value|@base64d)"'
```

Expected:

- `FRONTEND_SERVER_URL=http://127.0.0.1:8000`
- `PLATFORM_SERVICE_URL=http://127.0.0.1:8080`

## 6. Verification Checks

With port-forward running:

```bash
curl -I http://127.0.0.1:8000/
curl -i http://127.0.0.1:8080/api/v1/platform/agents
curl -i http://127.0.0.1:8000/api/v1/prompts/groups
```

Expected:

- UI returns `HTTP/1.1 200 OK`
- Agents endpoint returns `HTTP/1.1 200 OK`
- Prompts endpoint returns `HTTP/1.1 200 OK`

## 7. Known Failure Modes and Fixes

### A. `ErrImagePull` for `.../seaweedfs:3.97`

Symptom:

- Core init container fails pulling `gcr.io/gcp-maas-prod/chrislusf/seaweedfs:3.97`

Fix in this repo:

- `charts/solace-agent-mesh/templates/deployment_core.yaml` now uses `persistence-layer.seaweedfs.image.tag`
- With GCR, `custom-values.yaml` uses `3.97-compliant`

### B. Core stuck on `Init:0/2` at S3 readiness

Symptom:

- `s3-init` loops on "S3 API not ready yet..."

Fix in this repo:

- S3 readiness probe in `deployment_core.yaml` uses `wget -qO-` (GET) instead of `wget --spider` (HEAD)

### C. Agent deployer startup probe repeatedly failing

Symptom:

- `sam-agent-deployer:1.1.4` runs but keeps failing startup probe (`/startup`)

Fix:

- Set `samDeployment.agentDeployer.image.tag: 1.6.3` in `custom-values.yaml`

### D. UI shows "Failed to fetch" for Agents/Prompts

Typical causes:

- Wrong frontend/platform URLs (`sam.example.com`) in runtime env
- Missing platform port-forward (`8080`)
- Stale frontend tab using old config

Fix:

1. Ensure local overrides are set in `custom-values.yaml`
2. `helm upgrade ... -f custom-values.yaml`
3. Restart port-forward with all required ports
4. Hard refresh browser tab

## 8. Useful Day-2 Commands

```bash
# Release status
helm ls -n rafa-demos
helm status agent-mesh -n rafa-demos

# Events and logs
kubectl get events -n rafa-demos --sort-by=.lastTimestamp | tail -n 50
kubectl logs -n rafa-demos -l app.kubernetes.io/instance=agent-mesh --tail=200

# Pod details
kubectl describe pod -n rafa-demos <pod-name>
```

## 9. Security Note

Do not commit real credentials (broker password, LLM API key, docker auth json) into shared repositories. Rotate any credentials that were used in local testing.

