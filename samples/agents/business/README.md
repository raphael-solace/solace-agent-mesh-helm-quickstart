# Business Department Agent Pack (10 Agents)

This pack deploys 10 department-focused SAM agents into namespace `rafa-demos` using the `sam-agent` chart.

Included agents:

- `sam-agent-crm-revenue` (Salesforce)
- `sam-agent-hr-people` (Workday)
- `sam-agent-eng-product` (GitHub)
- `sam-agent-legal-counsel` (Harvey)
- `sam-agent-news-strategy` (Perplexity)
- `sam-agent-fin-finance` (SAP)
- `sam-agent-ops-operations` (n8n)
- `sam-agent-cx-customer` (Zendesk)
- `sam-agent-esg-sustainability` (Microsoft Fabric)
- `sam-agent-factory-manufacturing` (AWS IoT)

## Why this deployment method

This uses YAML-based deployment (Helm + `--set-file config.yaml=...`) so it is reproducible and can be versioned in Git.

## Deploy

From repo root:

```bash
samples/agents/business/generate-agent-configs.sh
samples/agents/business/deploy-business-agents.sh
```

Defaults:

- `NAMESPACE=rafa-demos`
- `BASE_RELEASE=sam-prescriptive-ops-workflow`

The deploy script reuses working runtime values from `BASE_RELEASE` (broker, LLM endpoint/key, image settings, persistence namespace), then applies each agent config.

## Verify

```bash
kubectl -n rafa-demos get deployments | rg 'sam-agent-(crm|hr|eng|legal|news|fin|ops|cx|esg|factory)'
kubectl -n rafa-demos get pods | rg 'sam-agent-(crm|hr|eng|legal|news|fin|ops|cx|esg|factory)'
```

## Remove

```bash
samples/agents/business/delete-business-agents.sh
```

## Notes

- Vendor names are encoded in each agent instruction profile.
- Actual API execution against Salesforce/Workday/GitHub/etc requires corresponding connectors/tools to be configured in SAM.
- These agents still run and provide structured planning/analysis with built-in tools while connector integration is staged.
- These are Helm-managed agent workloads. They are managed via Kubernetes and Helm rather than the platform "Enterprise Agents" CRUD list.
