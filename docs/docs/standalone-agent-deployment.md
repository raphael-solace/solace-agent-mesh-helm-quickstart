---
sidebar_position: 4
title: Standalone Agent and Workflow Deployment
---

# Standalone Agent and Workflow Deployment Guide

This guide explains how to deploy Solace Agent Mesh agents and workflows directly, without using the `agent-deployer` microservice.

:::note
Workflows and agents are deployed in the same way. A workflow usually involves multiple agents, which can be loaded either into a single pod or across multiple pods. As with agents, you must properly configure any supporting services such as artifacts, persistent storage, LLMs, event brokers, and namespaces.
:::

## Overview

There are two ways to deploy SAM agents and workflows:

1. **Via Agent Deployer** (Default): The SAM platform includes an agent-deployer microservice that dynamically deploys agents via the UI/API (only available for agents)
2. **Standalone Deployment** (This Guide): Deploy agents and workflows directly using `helm install` commands

## When to Use Standalone Deployment

Use standalone deployment when you:
- Want to deploy agents or workflows independently of the main SAM platform
- Need direct control over agent or workflow deployment and lifecycle
- Want to manage agents or workflows using GitOps workflows
- Are deploying agents or workflows in different clusters/namespaces

## Prerequisites

Before deploying a standalone agent or workflow, you need:

1. **Kubernetes cluster** with kubectl access
2. **Helm 3.19.0+** installed
3. **PostgreSQL database** (17+) - agent needs a database for state management
4. **S3-compatible storage** - agent needs object storage for file handling
5. **Solace Event Broker** - connection URL and credentials
6. **LLM Service** - API endpoint and credentials (e.g., OpenAI)
- A Kubernetes cluster with kubectl access
- Helm 3.19.0+ installed
- PostgreSQL database (version 17+). The agent needs a database for state management
- S3-compatible storage. The agent needs object storage for file handling.
- Solace Event Broker. You will need the connection URL and credentials.
- LLM Service (e.g., OpenAI). You will need the API endpoint and credentials.
- Agent configuration file. The YAML file defining which agents/services to enable.

## Deployment Steps

### Step 1: Prepare Agent or Workflow Configuration File

Create an agent or workflow configuration file (e.g., `my-agent-config.yaml`) that defines which agents and services to enable. Refer to the Solace Agent Mesh documentation for the configuration format.

Example agent structure (format may vary - consult SAM docs):
```yaml
agents:
  - name: web_request
    enabled: true
  - name: global
    enabled: true
# ... additional configuration
```

Example workflow structure:
```yaml
apps:
  - name: my_workflow
    app_module: solace_agent_mesh.workflow.app
    broker:
      # ... broker configuration

    app_config:
      namespace: ${NAMESPACE}
      agent_name: "MyWorkflow"

      workflow:
        description: "Process incoming orders"
        version: "1.0.0"

        input_schema:
          type: object
          properties:
            order_id:
              type: string
          required: [order_id]

        nodes:
          - id: validate_order
            type: agent
            agent_name: "OrderValidator"
            input:
              order_id: "{{workflow.input.order_id}}"

          - id: process_payment
            type: agent
            agent_name: "PaymentProcessor"
            depends_on: [validate_order]
            input:
              order_data: "{{validate_order.output}}"

        output_mapping:
          status: "{{process_payment.output.status}}"
          confirmation: "{{process_payment.output.confirmation_number}}"
```

### Step 2: Prepare Values File

Download the sample values file:
```bash
curl -O https://raw.githubusercontent.com/SolaceProducts/solace-agent-mesh-helm-quickstart/main/samples/agent/agent-standalone-values.yaml
```

Edit `agent-standalone-values.yaml` and configure:

**Required Configuration:**
- `agentId`: Unique identifier for this agent or workflow instance
- `solaceBroker`: Broker connection details
- `llmService`: LLM service configuration
- `persistence`: Database and S3 credentials

**Persistence Options:**

**Option 1: Use Existing Secrets (Recommended)**
```yaml
persistence:
  existingSecrets:
    database: "my-database-secret"  # Secret must contain DATABASE_URL
    s3: "my-s3-secret"              # Secret must contain S3_ENDPOINT_URL, S3_BUCKET_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

**Option 2: Provide Credentials Directly**
```yaml
persistence:
  database:
    url: "postgresql+psycopg2://user:password@hostname:5432/dbname"
  s3:
    endpointUrl: "https://s3.amazonaws.com"
    bucketName: "my-bucket"
    accessKey: "your-access-key"
    secretKey: "your-secret-key"
    region: "us-east-1"
```

### Step 3: Create Service Account (If Not Exists)

The agent or workflow needs a Kubernetes service account with permissions to access secrets:

```bash
kubectl create serviceaccount solace-agent-mesh-sa -n your-namespace
```

### Step 4: Install the Agent or Workflow Chart

- **Agent**
```bash
helm install my-agent solace-agent-mesh/sam-agent \
  -f agent-standalone-values.yaml \
  --set-file config.agentYaml=./my-agent-config.yaml \
  -n your-namespace
```

- **Workflow**
```bash
helm install my-workflow solace-agent-mesh/sam-agent \
  -f agent-standalone-values.yaml \
  --set-file config.agentYaml=./my-workflow-config.yaml \
  -n your-namespace
```

**Important Parameters:**
- `my-agent`: Helm release name (choose a unique name per agent or workflow)
- `-f agent-standalone-values.yaml`: Your customized values file
- `--set-file config.agentYaml=...`: Path to your agent or workflow or workflow configuration file
- `-n your-namespace`: Kubernetes namespace to deploy into

### Step 5: Verify Deployment

Check the agent or workflow pod is running:
```bash
kubectl get pods -n your-namespace -l app.kubernetes.io/name=sam-agent
```

Check the agent or workflow logs:
```bash
kubectl logs -n your-namespace -l app.kubernetes.io/name=sam-agent --tail=100 -f
```

## Configuration Reference

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `deploymentMode` | Deployment mode (must be "standalone") | `standalone` |
| `agentId` | Unique agent identifier | `my-custom-agent` |
| `solaceBroker.url` | Solace broker connection URL | `wss://broker.solace.cloud:443` |
| `solaceBroker.username` | Broker username | `solace-user` |
| `solaceBroker.password` | Broker password | `password123` |
| `solaceBroker.vpn` | Broker VPN name | `default` |
| `llmService.generalModelName` | LLM model name | `gpt-4o` |
| `llmService.endpoint` | LLM API endpoint | `https://api.openai.com/v1` |
| `llmService.apiKey` | LLM API key | `sk-...` |
| `persistence.database.url` | Database connection URL | `postgresql+psycopg2://...` |
| `persistence.s3.endpointUrl` | S3 endpoint | `https://s3.amazonaws.com` |
| `persistence.s3.bucketName` | S3 bucket name | `my-bucket` |
| `config.agentYaml` | Agent configuration (via --set-file) | (file path) |

### Database Requirements

The agent requires a PostgreSQL database (version 17+). The init container will automatically:
1. Create a database user (based on `agentId` and `namespaceId`)
2. Create a database for the agent
3. Grant necessary permissions

**Database URL Format:**
```
postgresql+psycopg2://username:password@hostname:port/database_name
```

**For Supabase Connection Pooler:**
The chart automatically detects and handles Supabase tenant ID qualification if present in the database secret.

### S3 Storage Requirements

The agent requires S3-compatible storage for file handling. Supported providers:
- Amazon S3
- MinIO
- SeaweedFS
- Any S3-compatible object storage

**Required S3 Configuration:**
- Endpoint URL
- Bucket name (must exist)
- Access credentials (key ID and secret key)

## Comparison: Deployer vs Standalone Mode

| Aspect | Agent Deployer Mode | Standalone Mode |
|--------|-------------------|-----------------|
| **Deployment** | Via SAM UI/API | Via `helm install` command |
| **Configuration Discovery** | Auto-discovers persistence secrets | Explicit configuration required |
| **Agent Config** | Provided by deployer | Must provide via `--set-file` |
| **Use Case** | Dynamic agent management | Static/GitOps workflows |
| **Lifecycle** | Managed by SAM platform | Managed by Helm/K8s |

## Troubleshooting

### Agent Pod Not Starting

**Check pod events:**
```bash
kubectl describe pod -n your-namespace -l app.kubernetes.io/name=sam-agent
```

**Common issues:**
- Missing or incorrect database credentials
- Database not accessible from cluster
- S3 credentials invalid
- Missing agent configuration file

### Init Container Fails

The init container creates the database and user. Check logs:
```bash
kubectl logs -n your-namespace -l app.kubernetes.io/name=sam-agent -c db-init
```

**Common issues:**
- Admin credentials in persistence secret are incorrect
- Database server not reachable
- Admin user lacks CREATE DATABASE permissions

### Agent Configuration Errors

If the agent starts but fails to initialize:
```bash
kubectl logs -n your-namespace -l app.kubernetes.io/name=sam-agent -c sam
```

**Common issues:**
- Invalid agent configuration YAML format
- Referenced agents/services don't exist
- Missing required configuration fields

## Upgrading Agents or Workflows

To upgrade an agent or workflow deployment:

- **Agent**
```bash
helm upgrade my-agent solace-agent-mesh/sam-agent \
  -f agent-standalone-values.yaml \
  --set-file config.agentYaml=./my-agent-config.yaml \
  -n your-namespace
```

- **Workflow**
```bash
helm upgrade my-workflow solace-agent-mesh/sam-agent \
  -f agent-standalone-values.yaml \
  --set-file config.agentYaml=./my-workflow-config.yaml \
  -n your-namespace
```

## Uninstalling Agents or Workflows

To remove an agent or workflow:

- **Agent**
```bash
helm uninstall my-agent -n your-namespace
```

- **Workflow**
```bash
helm uninstall my-workflow -n your-namespace
```

**Note:** This does NOT delete:
- The agent's database (manual cleanup required)
- Any data in S3 storage
- Any secrets you created manually

## Advanced Configuration

### Using Separate Database and S3 Secrets

For better security, create separate secrets for database and S3:

```bash
# Database secret
kubectl create secret generic my-db-secret \
  --from-literal=DATABASE_URL='postgresql+psycopg2://user:pass@host:5432/db' \
  -n your-namespace

# S3 secret
kubectl create secret generic my-s3-secret \
  --from-literal=S3_ENDPOINT_URL='https://s3.amazonaws.com' \
  --from-literal=S3_BUCKET_NAME='my-bucket' \
  --from-literal=AWS_ACCESS_KEY_ID='AKIAIOSFODNN7EXAMPLE' \
  --from-literal=AWS_SECRET_ACCESS_KEY='wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' \
  -n your-namespace
```

Then reference them in values:
```yaml
persistence:
  existingSecrets:
    database: "my-db-secret"
    s3: "my-s3-secret"
```

### Custom Resource Limits

Adjust resource requests/limits based on your workload:

```yaml
resources:
  sam:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1024Mi
```

### Additional Environment Variables

Add custom environment variables:

```yaml
environmentVariables:
  MY_CUSTOM_VAR: "value"
  ANOTHER_VAR: "another_value"
```

## Next Steps

- See Solace Agent Mesh documentation for agent or workflow configuration format
- Set up monitoring and alerting for your agents
- Implement backup strategies for agent databases
- Consider using external-secrets operator for credential management
