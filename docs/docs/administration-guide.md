---
sidebar_position: 6
title: Administration Guide
---

# SAM Administration Guide

This guide focuses on operating Solace Agent Mesh (SAM) after initial deployment.

## 1. Environment Strategy

Use separate namespaces (or clusters) for each environment:

- `dev` for rapid testing
- `staging` for pre-production validation
- `prod` for stable runtime

Recommendations:

- Use separate values files per environment
- Use unique `global.persistence.namespaceId` per environment
- Keep release names consistent (for example: `agent-mesh`)

## 2. Secrets and Credential Hygiene

Minimum secrets to protect:

- Pull secret (`kubernetes.io/dockerconfigjson`)
- Broker credentials
- LLM API keys
- OIDC client secrets (if enabled)
- Database credentials (external persistence mode)

Best practices:

- Store secrets outside Git
- Use a secret manager (Vault, External Secrets Operator, cloud KMS)
- Rotate credentials on schedule and after incidents
- Grant namespace-scoped least privilege

Quick check:

```bash
kubectl get secrets -n <namespace>
kubectl get serviceaccount solace-agent-mesh-sa -n <namespace> -o yaml
```

## 3. Upgrades and Change Management

Before each upgrade:

1. Snapshot/backup persistence data
2. Test in staging
3. Capture current values
4. Run upgrade
5. Validate health and key workflows

Commands:

```bash
helm get values agent-mesh -n <namespace> > current-values.yaml
helm upgrade agent-mesh charts/solace-agent-mesh -f <values-file> -n <namespace>
kubectl rollout status deployment/agent-mesh-core -n <namespace>
kubectl rollout status deployment/agent-mesh-agent-deployer -n <namespace>
```

Pin versions intentionally:

- SAM image tag (`samDeployment.image.tag`)
- Agent deployer image tag (`samDeployment.agentDeployer.image.tag`)
- Chart version (for remote repo installs)

## 4. Persistence Operations

Bundled persistence (`global.persistence.enabled: true`) is good for local/dev and limited demos.

For production:

- Prefer external managed PostgreSQL + S3-compatible storage
- Define backup and retention policies
- Validate restore procedure regularly

For bundled mode:

- Monitor PVC capacity and growth
- Keep storage class behavior understood (`WaitForFirstConsumer` in cloud multi-AZ)

## 5. Health and Observability

Monitor:

- Pod readiness and restarts
- Kubernetes events
- SAM logs
- Platform API health
- Broker connectivity

Core commands:

```bash
kubectl get pods -n <namespace> -l app.kubernetes.io/instance=agent-mesh
kubectl get events -n <namespace> --sort-by=.lastTimestamp | tail -n 50
kubectl logs -n <namespace> -l app.kubernetes.io/instance=agent-mesh --tail=200
```

API checks (via port-forward or ingress/LB):

```bash
curl -i http://<sam-host-or-local>:8080/api/v1/platform/health
curl -i http://<sam-host-or-local>/api/v1/prompts/groups
```

## 6. Capacity and Resource Planning

Track:

- CPU/memory utilization
- Node disk pressure (large image pulls)
- Persistent volume usage

Actions:

- Tune `samDeployment.resources.*`
- Ensure nodes have enough disk (>=30GB recommended in docs)
- Set alerts for restart loops and storage thresholds

## 7. Network and Access Control

Decide your access model clearly:

- Ingress (recommended for stable hostnames/TLS)
- LoadBalancer
- Local port-forward (dev only)

For local workflows, keep URL config consistent with forwarded ports. Mismatched frontend/platform URLs are a common source of "Failed to fetch" errors.

## 8. Incident Response Playbook

When users report UI/API failures:

1. Confirm pods are Ready
2. Check recent events for pull/probe/storage errors
3. Validate runtime URL env (`FRONTEND_SERVER_URL`, `PLATFORM_SERVICE_URL`)
4. Curl UI and platform endpoints from the same path users are using
5. Check core logs for 4xx/5xx and connection failures

Targeted checks:

```bash
kubectl get secret -n <namespace> <release>-environment -o json | \
  jq -r '.data | to_entries[] | select(.key|test("FRONTEND_SERVER_URL|PLATFORM_SERVICE_URL")) | "\(.key)=\(.value|@base64d)"'
```

## 9. Backup and Disaster Recovery

Document these explicitly for your deployment:

- Recovery Point Objective (RPO)
- Recovery Time Objective (RTO)
- Backup frequency and retention
- Restore owner and on-call runbook

Test restores on a schedule. Unvalidated backups are not a recovery plan.

## 10. Governance and Maintenance Cadence

Suggested cadence:

- Daily: health/events/restarts review
- Weekly: resource trend review and failed task/error review
- Monthly: credential rotation checks, dependency/version review, backup restore test
- Quarterly: DR exercise and security posture review

