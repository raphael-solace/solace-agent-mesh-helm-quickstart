---
sidebar_position: 3
title: Persistence Configuration
---

# Persistence Configuration

SAM requires persistent storage for session data and artifacts. This page covers all persistence-related configuration options.

## Overview

SAM uses two types of persistent storage:

- **PostgreSQL Database**: Stores session metadata, user data, and application state
- **S3-Compatible Storage**: Stores artifacts, files, and other binary data in two separate buckets:
  - **Artifacts bucket**: Stores workflow artifacts and temporary files (fully private)
  - **Connector specs bucket**: Stores OpenAPI connector specification files (public read access, authenticated write only)

### S3 Bucket Configuration Details

SAM requires **two separate S3 buckets** with different access requirements:

| Bucket Type | Purpose | Access Requirements | Features Enabled |
|-------------|---------|---------------------|------------------|
| **Artifacts** | Workflow artifacts, temporary files | Fully private (authenticated read/write only) | Core workflow functionality |
| **Connector Specs** | OpenAPI specification files | Public read, authenticated write | OpenAPI Connector feature for automatic REST API integrations |

**Why two buckets?**
- Different lifecycle and access patterns: artifacts are temporary workflow data, while connector specs are long-lived infrastructure files
- Security isolation: agents must download connector specs at startup without authentication, but workflow artifacts must remain private
- Critical infrastructure: agents cannot start without access to connector specification files

You can choose between two persistence strategies:

| Strategy | Use Case | Components |
|----------|----------|------------|
| **Bundled Persistence** | Development, demos, POC | In-cluster PostgreSQL + SeaweedFS |
| **External Persistence** | Production deployments | Managed PostgreSQL + S3 (e.g., AWS RDS, Supabase, NeonDB) |

## Option 1: Bundled Persistence (Dev/POC Only)

**Not recommended for production.** The chart can deploy single-instance PostgreSQL and SeaweedFS for quick start, demos, and proof-of-concept deployments.

The bundled SeaweedFS is automatically configured with both required buckets and appropriate security:

**Artifacts Bucket** (`{namespaceId}`):
- Fully private - authenticated read/write only
- No anonymous access
- Stores temporary workflow artifacts

**Connector Specs Bucket** (`{namespaceId}-connector-specs`):
- Authenticated write access (SAM service only)
- Anonymous/public read access (required for agents to download OpenAPI specifications)
- Stores critical infrastructure files needed for agent startup

### Basic Configuration

```yaml
global:
  persistence:
    enabled: true
    namespaceId: "my-sam-instance"  # Must be unique per SAM installation
```

:::tip Upgrading from ≤1.1.0?
If you have an existing bundled persistence deployment from chart version ≤1.1.0, a one-time migration is required. See [Bundled Persistence VCT Labels](/#bundled-persistence-vct-labels-upgrading-from-110) in the Upgrading guide.
:::

### Image Registry Configuration

By default, the bundled persistence components pull images from Docker Hub:
- PostgreSQL: `postgres:18.0`
- SeaweedFS: `chrislusf/seaweedfs:3.97`

#### Using Solace's Private GCR Registry

To avoid Docker Hub rate limits or when deploying in air-gapped environments, you can use Solace's private GCR registry. When using any of Solace's GCR registries, you must specify GCR-specific image tags:

```yaml
global:
  imageRegistry: gcr.io/gcp-maas-prod
  persistence:
    enabled: true
    namespaceId: "my-sam-instance"

samDeployment:
  imagePullSecret: "your-image-pull-secret"  # Required - see Step 2 in Getting Started

persistence-layer:
  postgresql:
    image:
      tag: "18.0-trixie"  # Required for GCR (Docker Hub default: "18.0")
  seaweedfs:
    image:
      tag: "3.97-compliant"  # Required for GCR (Docker Hub default: "3.97")
```

> **Note**: The image pull secret is required for accessing Solace's private GCR registry. See [Configure Image Pull Secret](/#step-2-configure-image-pull-secret) in the Getting Started guide.

| Component  | Docker Hub Tag | GCR Tag         |
|------------|----------------|-----------------|
| PostgreSQL | `18.0`         | `18.0-trixie`   |
| SeaweedFS  | `3.97`         | `3.97-compliant`|

#### Custom or Self-Managed Images

For advanced use cases where you need to use custom images (e.g., self-hosted registries, modified images, or air-gapped environments), you can override the full image configuration:

```yaml
persistence-layer:
  postgresql:
    image:
      registry: "my-registry.example.com"  # Custom registry (overrides global.imageRegistry)
      repository: "my-org/custom-postgres" # Custom image name (default: "postgres")
      tag: "18.0-custom"                   # Custom tag (default: "18.0")
  seaweedfs:
    image:
      registry: "my-registry.example.com"
      repository: "my-org/custom-seaweedfs" # Default: "chrislusf/seaweedfs"
      tag: "3.97-custom"                    # Default: "3.97"
```

**Image Configuration Precedence:**
1. `persistence-layer.[postgresql|seaweedfs].image.registry` (if set) takes precedence over `global.imageRegistry`
2. If neither registry is set, images pull from Docker Hub by default
3. `repository` and `tag` are always component-specific and can be overridden independently

### Storage Class Configuration

By default, the bundled persistence uses the cluster's default storage class. To specify a custom storage class:

```yaml
persistence-layer:
  postgresql:
    persistence:
      storageClassName: "gp3"  # e.g., gp3 for AWS EBS
      size: "10Gi"  # Default: 10Gi
  seaweedfs:
    persistence:
      storageClassName: "gp3"
      size: "20Gi"  # Default: 20Gi
```

### Important Caveats

1. **PVCs persist after uninstall**: When you run `helm uninstall`, the PersistentVolumeClaims (PVCs) are not automatically deleted. This is by design to prevent accidental data loss. To fully clean up:
   ```bash
   kubectl delete pvc -l app.kubernetes.io/namespace-id=<your-namespace-id>
   ```

2. **Single instance only**: The bundled persistence deploys single-instance databases with no high availability or automatic failover.

3. **No automatic backups**: You are responsible for implementing backup strategies for the bundled databases.

4. **Docker Hub rate limits**: If not using a private registry, you may encounter Docker Hub rate limits during image pulls.

## Option 2: External Persistence (Production Recommended)

For production deployments, use managed PostgreSQL and S3-compatible storage services for better scalability, reliability, and separation of concerns.

When using external persistence, the bundled persistence layer is disabled by default (`global.persistence.enabled: false`).

### Database Requirements

- PostgreSQL version 17 or higher
- Admin credentials with `SUPERUSER` privileges (recommended) or at minimum `CREATEROLE` and `CREATEDB`
- SAM's init container uses admin credentials to automatically create users and databases for the application and any deployed agents

### Basic External Configuration

```yaml
global:
  persistence:
    enabled: false  # Default, can be omitted
    namespaceId: "my-sam-instance"

dataStores:
  database:
    protocol: "postgresql+psycopg2"
    host: "your-postgres-host"
    port: "5432"
    adminUsername: "your-db-admin-user"
    adminPassword: "your-db-admin-password"
    applicationPassword: "your-secure-app-password"  # REQUIRED: Password for all app database users
  s3:
    endpointUrl: "your-s3-endpoint-url"
    bucketName: "your-bucket-name"
    connectorSpecBucketName: "your-connector-specs-bucket-name"
    accessKey: "your-s3-access-key"
    secretKey: "your-s3-secret-key"
```

**Important**: The `applicationPassword` field is **required** when using external persistence. This single password will be used for all database users created by SAM (webui, orchestrator, platform, and all agents).

**Password Rotation Limitation**: Once database users are created for a given `namespaceId`, the `applicationPassword` cannot be changed. If you need to change the password, you must either use a new `namespaceId` (which creates new databases and users), or manually update the passwords directly in the database.

### Provider-Specific Examples

#### Supabase with Connection Pooler

If using Supabase with the connection pooler (required for IPv4 networks):

```yaml
dataStores:
  database:
    protocol: "postgresql+psycopg2"
    host: "aws-1-us-east-1.pooler.supabase.com"
    port: "5432"
    adminUsername: "postgres"
    adminPassword: "your-supabase-postgres-password"
    applicationPassword: "your-secure-app-password"
    supabaseTenantId: "your-project-id"  # Extract from connection string
  s3:
    endpointUrl: "https://your-project-id.storage.supabase.co/storage/v1/s3"
    bucketName: "your-bucket-name"
    connectorSpecBucketName: "your-connector-specs-bucket-name"
    accessKey: "your-supabase-s3-access-key"
    secretKey: "your-supabase-s3-secret-key"
```

**Note**: If using Supabase's Direct Connection with IPv4 addon, omit the `supabaseTenantId` field.

#### AWS RDS + S3

```yaml
dataStores:
  database:
    protocol: "postgresql+psycopg2"
    host: "mydb.abc123.us-east-1.rds.amazonaws.com"
    port: "5432"
    adminUsername: "postgres"
    adminPassword: "your-rds-password"
    applicationPassword: "your-secure-app-password"
  s3:
    endpointUrl: "https://s3.us-east-1.amazonaws.com"
    bucketName: "my-sam-artifacts"
    connectorSpecBucketName: "my-sam-connector-specs"
    accessKey: "AKIAIOSFODNN7EXAMPLE"
    secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

#### NeonDB

```yaml
dataStores:
  database:
    protocol: "postgresql+psycopg2"
    host: "ep-cool-name-123456.us-east-2.aws.neon.tech"
    port: "5432"
    adminUsername: "neondb_owner"
    adminPassword: "your-neon-password"
    applicationPassword: "your-secure-app-password"
  s3:
    # Configure your preferred S3-compatible storage
    endpointUrl: "https://s3.amazonaws.com"
    bucketName: "my-sam-artifacts"
    connectorSpecBucketName: "my-sam-connector-specs"
    accessKey: "your-access-key"
    secretKey: "your-secret-key"
```

### AWS S3 Bucket Setup and Policy Requirements

When using external AWS S3, you must create **both buckets** before deploying SAM.

**Create the buckets:**

```bash
# Create artifacts bucket (private)
aws s3 mb s3://your-bucket-name --region us-east-1

# Create connector specs bucket (will configure public read next)
aws s3 mb s3://your-connector-specs-bucket-name --region us-east-1
```

#### Connector Specs Bucket: Public Read Policy

The connector specs bucket **requires public read access** so agents can download OpenAPI specification files during startup without authentication. This is a critical security requirement that enables the OpenAPI Connector feature.

**Why public read access?**
- Agents need to download connector specification files immediately at startup
- Authentication credentials are not available to agents until after startup completes
- These files contain API schemas and endpoints but no sensitive data (credentials, keys, etc.)
- Write access remains restricted to the SAM service only (using S3 access keys)

**Security considerations:**
- **Safe to make public**: Connector specification files contain only API schemas, endpoints, and data models
- **No credentials**: Never store API keys, passwords, or secrets in connector specifications
- **Write protection**: Only the SAM service (with S3 credentials) can upload/modify files
- **Review specs before upload**: Ensure connector specs don't contain internal URLs or sensitive metadata you don't want public

**Apply public read policy:**

Save this policy as `connector-specs-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::your-connector-specs-bucket-name/*"
  }]
}
```

Apply the policy:

```bash
aws s3api put-bucket-policy \
  --bucket your-connector-specs-bucket-name \
  --policy file://connector-specs-policy.json
```

#### Important Security Notes

**Artifacts bucket (private):**
- Should remain **fully private** (default AWS S3 behavior)
- No public access policy needed
- Contains workflow artifacts and temporary files
- Only accessible with S3 credentials

**Connector specs bucket (public read):**
- Needs **public read** access (anonymous GetObject)
- **Private write** access (only SAM service with credentials can upload)
- Contains OpenAPI specification files for REST API integrations
- Enables the OpenAPI Connector feature
- Replace `your-connector-specs-bucket-name` in the policy with your actual bucket name

## Troubleshooting

### Init Container Stuck in Pending/CrashLoopBackOff

**Symptoms**: The `agent-mesh-core` pod shows init containers waiting or failing.

**Common causes**:
1. **Image pull failures**: Check if using GCR registry without specifying GCR-specific image tags
2. **Storage class issues**: Verify the storage class exists and can provision volumes
3. **Database connectivity**: For external persistence, verify network connectivity to the database

**Debug commands**:
```bash
# Check pod status and events
kubectl describe pod -l app.kubernetes.io/name=solace-agent-mesh

# Check init container logs
kubectl logs <pod-name> -c init-db-provision

# Verify PVC status
kubectl get pvc
```

### PVC Stuck in Pending

**Symptoms**: PersistentVolumeClaims remain in `Pending` state.

**Common causes**:
1. No default storage class configured
2. Specified storage class doesn't exist
3. Storage provisioner issues

**Solution**: Specify an existing storage class explicitly:
```yaml
persistence-layer:
  postgresql:
    persistence:
      storageClassName: "your-storage-class"
```

### Docker Hub Rate Limit Errors

**Symptoms**: Image pull errors mentioning rate limits.

**Solution**: Use Solace's private GCR registry (see [Image Registry Configuration](#image-registry-configuration)).
