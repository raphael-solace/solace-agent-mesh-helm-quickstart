---
sidebar_position: 2
title: Network Configuration
---

# SAM Network Configuration Guide

This guide explains the different ways to expose SAM (Solace Agent Mesh) to the internet and when to use each approach.

## Table of Contents

- [Overview](#overview)
- [Service Exposure Options](#service-exposure-options)
  - [Option 1: ClusterIP (Default)](#option-1-clusterip-default)
  - [Option 2: NodePort](#option-2-nodeport)
  - [Option 3: LoadBalancer](#option-3-loadbalancer)
  - [Option 4: Ingress (Recommended for Production)](#option-4-ingress-recommended-for-production)
- [Ingress Configuration](#ingress-configuration)
  - [AWS ALB Ingress](#aws-alb-ingress)
  - [NGINX Ingress](#nginx-ingress)
  - [Other Ingress Controllers](#other-ingress-controllers)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Decision Matrix](#decision-matrix)
- [Examples](#examples)

---

## Overview

SAM requires external access for users to access the Web UI and for OAuth2/OIDC authentication flows. Kubernetes provides multiple methods to expose services externally, each with different trade-offs.

**SAM exposes these ports:**
- **Port 80/443**: Web UI (HTTP/HTTPS)
- **Port 8080/4443**: Platform Service API (HTTP/HTTPS) - Enterprise feature
- **Port 5050**: OAuth2 Authentication Server

All ports are HTTP-based and can be exposed through any of the methods below.

**Note:** Platform Service (port 8080/4443) is only available in SAM Enterprise deployments.

---

## Service Exposure Options

### Option 1: ClusterIP (Default)

**What it is:** Internal-only access within the Kubernetes cluster.

**When to use:**
- Development/testing with `kubectl port-forward`
- When using Ingress for external access
- Maximum security (no external exposure)

**Configuration:**
```yaml
service:
  type: ClusterIP
```

**Access SAM:**
```bash
# Port-forward to local machine
kubectl port-forward -n <namespace> svc/sam 8443:443

# Access at https://localhost:8443
```

**Pros:**
- ✅ Most secure (no external exposure)
- ✅ No cloud costs
- ✅ Works everywhere

**Cons:**
- ❌ Requires port-forward for local access
- ❌ Not suitable for team/production use

#### Local Development with Port-Forward

For local development (minikube, kind, Docker Desktop), you have two options:

**Option A: Use the local development sample file (Recommended)**

The [`local-k8s-values.yaml`](https://github.com/SolaceProducts/solace-agent-mesh-helm-quickstart/blob/main/samples/values/local-k8s-values.yaml) sample includes CORS configuration that allows any localhost port:

```bash
helm install agent-mesh solace-agent-mesh/solace-agent-mesh -f local-k8s-values.yaml
```

With this sample, you can use any port or even `minikube service`:
```bash
# Any port works
kubectl port-forward svc/<release-name> 9000:80 9001:8001

# Or use minikube service
minikube service <release-name>
```

**Option B: Use specific ports (if not using the sample file)**

If you're using custom values without `sam.cors.allowedOriginRegex`, use these pre-configured ports:

| Port | Service | Purpose |
|------|---------|---------|
| 8000 | WebUI | Web interface and Gateway API |
| 8001 | Platform Service | Enterprise features (agent builder, deployments, connectors) |

```bash
kubectl port-forward -n <namespace> svc/<release-name> 8000:80 8001:8001
```

**Why port 8000?** It's pre-configured in the Platform Service CORS allowed origins. Using other ports without the CORS regex will cause cross-origin errors.

**Pre-configured CORS origins (without regex):**
- `http://localhost:8000` ✅
- `http://localhost:3000` ✅
- Other ports ❌ (will cause CORS errors)

**Adding CORS regex to custom values:**

If you have a custom values file and want to enable any localhost port, add:

```yaml
sam:
  cors:
    allowedOriginRegex: "https?://(localhost|127\\.0\\.0\\.1):\\d+"
```

This uses Python's `re.fullmatch()` to match origins. Leave empty for production deployments.

---

### Option 2: NodePort

**What it is:** Exposes service on each node's IP at a static port (30000-32767 range).

**When to use:**
- Development environments without Ingress
- Bare-metal clusters
- Testing with team members
- Quick external access

**Configuration:**
```yaml
service:
  type: NodePort
  nodePorts:
    https: 30443  # Optional: specify port (or auto-assign)
    http: 30080
    auth: 30050
```

**Access SAM:**
```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

# Get assigned NodePort
NODE_PORT=$(kubectl get svc sam -o jsonpath='{.spec.ports[?(@.name=="webui-tls")].nodePort}')

# Access at https://$NODE_IP:$NODE_PORT
```

**Pros:**
- ✅ Simple setup
- ✅ No external dependencies
- ✅ Works in any Kubernetes environment

**Cons:**
- ❌ Requires non-standard ports (30000-32767)
- ❌ Must know node IPs
- ❌ Not recommended for production

---

### Option 3: LoadBalancer

**What it is:** Provisions a cloud load balancer with an external IP.

**When to use:**
- Simple cloud deployments (AWS, GCP, Azure)
- Quick production setup
- No Ingress controller available
- Non-HTTP protocols (not applicable to SAM)

**Configuration:**
```yaml
service:
  type: LoadBalancer
  annotations:
    # AWS NLB example
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb-ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

**Access SAM:**
```bash
# Get external IP
kubectl get svc sam -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Configure DNS to point to this address
# Access at https://sam.example.com
```

**Pros:**
- ✅ Easy to set up
- ✅ Cloud-native
- ✅ Automatic external IP

**Cons:**
- ❌ **Costs money** (one load balancer per service)
- ❌ Only works with cloud providers or MetalLB
- ❌ Less efficient than Ingress for multiple services

**Cost Comparison:**
- 1 LoadBalancer service = 1 cloud load balancer (~$15-30/month)
- 10 services = 10 load balancers ($150-300/month)
- 1 Ingress = 1 load balancer for all services (~$15-30/month total)

---

### Option 4: Ingress (Recommended for Production)

**What it is:** HTTP/HTTPS routing layer that uses a single load balancer for multiple services.

**When to use:**
- **Production deployments** ✅
- Cost optimization
- Advanced routing needs (path-based, host-based)
- TLS management with cert-manager
- Integration with WAF, rate limiting, etc.

**Benefits:**
- ✅ **Cost-effective** (one LB for many services)
- ✅ **Layer 7 routing** (HTTP/HTTPS)
- ✅ **Centralized TLS** management
- ✅ **Advanced features** (URL rewrites, authentication, etc.)
- ✅ **Industry standard** for HTTP applications

**Configuration Overview:**
```yaml
service:
  type: ClusterIP  # Ingress sits in front of ClusterIP service

ingress:
  enabled: true
  className: "nginx"  # or "alb", "traefik", etc.
  autoConfigurePaths: true  # Recommended - automatically configures all routes
  host: "sam.example.com"
  annotations: {}
  tls: []
```

See [Ingress Configuration](#ingress-configuration) section below for detailed examples.

---

## Ingress Configuration

SAM provides two approaches for configuring ingress paths: **automatic** (recommended) and **manual** (advanced).

### Automatic Path Configuration (Recommended)

The chart automatically configures all required ingress paths when `autoConfigurePaths: true` (default):

```yaml
ingress:
  enabled: true
  className: "alb"  # or "nginx", "gce", etc.
  autoConfigurePaths: true  # Default - automatically configures all routes
  host: "sam.example.com"  # Optional, leave empty for ALB
  annotations:
    # Provider-specific annotations
```

**What gets configured automatically:**
- `/login`, `/callback`, `/is_token_valid`, `/user_info`, `/refresh_token`, `/exchange-code` → Auth Service (port 5050)
- `/api/v1/platform/*` → Platform Service (port 8080/4443)
- `/*` → WebUI Service (port 80/443)

**Benefits:**
- ✅ Simpler configuration (3-5 lines vs 20+ lines)
- ✅ Always up-to-date with latest routing requirements
- ✅ Seamless upgrades (new routes added automatically)
- ✅ Reduces configuration errors

### Manual Path Configuration (Advanced)

For advanced use cases requiring custom routing, set `autoConfigurePaths: false`:

```yaml
ingress:
  enabled: true
  className: "nginx"
  autoConfigurePaths: false  # Advanced: manual control
  hosts:
    - host: "sam.example.com"
      paths:
        - path: /api/v1/platform
          pathType: Prefix
          portName: platform
        - path: /login
          pathType: Prefix
          portName: auth
        - path: /
          pathType: Prefix
          portName: webui
```

**When to use manual configuration:**
- Custom path routing requirements
- Integration with existing ingress rules
- Advanced traffic splitting scenarios

**Note:** When using manual configuration, you must include all required paths (auth, platform, webui) or platform features will not be accessible.

---

### AWS ALB Ingress

**Best for:** AWS EKS clusters

**Prerequisites:**
- AWS Load Balancer Controller installed
- ACM certificate for TLS
- Subnets configured for ALB

**Recommended Configuration (Automatic Paths):**

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # ALB handles TLS termination

ingress:
  enabled: true
  className: "alb"

  # Automatic path configuration (recommended)
  autoConfigurePaths: true
  host: ""  # Empty for ALB (accepts all traffic)

  annotations:
    # ALB configuration
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'

    # TLS certificate (ACM)
    # REQUIRED: Triggers HTTPS URL generation for OAuth
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:REGION:ACCOUNT:certificate/ID

    # SSL redirect
    alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": { "Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'

    # Health check (checks webui service for overall pod health)
    # Note: Platform service has its own health endpoint at /api/v1/platform/health
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "30"
    alb.ingress.kubernetes.io/success-codes: "200"

    # REQUIRED: Subnets for ALB placement
    alb.ingress.kubernetes.io/subnets: subnet-xxx,subnet-yyy

    # External DNS (optional)
    external-dns.alpha.kubernetes.io/hostname: sam.example.com
```

**Advanced Configuration (Manual Paths):**

<details>
<summary>Click to expand manual path configuration</summary>

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # ALB handles TLS termination

ingress:
  enabled: true
  className: "alb"

  # Manual path configuration
  autoConfigurePaths: false

  annotations:
    # Same annotations as above
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:REGION:ACCOUNT:certificate/ID
    alb.ingress.kubernetes.io/actions.ssl-redirect: '{"Type": "redirect", "RedirectConfig": { "Protocol": "HTTPS", "Port": "443", "StatusCode": "HTTP_301"}}'
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/subnets: subnet-xxx,subnet-yyy
    external-dns.alpha.kubernetes.io/hostname: sam.example.com

  hosts:
    - host: ""  # Empty for ALB (accepts all traffic)
      paths:
        # Auth endpoints → port 5050
        - path: /login
          pathType: Prefix
          portName: auth
        - path: /callback
          pathType: Prefix
          portName: auth
        - path: /is_token_valid
          pathType: Prefix
          portName: auth
        - path: /exchange-code
          pathType: Prefix
          portName: auth
        # Platform service API (enterprise only, must be before broader /api paths)
        # Health endpoint: /api/v1/platform/health
        - path: /api/v1/platform
          pathType: Prefix
          portName: platform
        # Web UI → port 80 (HTTP backend, TLS at ALB)
        - path: /
          pathType: Prefix
          portName: webui
```

</details>


**Traffic Flow:**
```
Client (HTTPS)
   ↓
AWS ALB (TLS termination via ACM)
   ↓
HTTP (internal VPC traffic)
   ↓
Kubernetes Service (routes to appropriate port based on path)
   ├─ /api/v1/platform/* → Platform Service (port 8080 → 8001)
   ├─ /login, /callback, etc. → Auth Service (port 5050)
   └─ / (catch-all) → Web UI (port 80 → 8000)
   ↓
SAM Pods
```

**Key Points:**
- TLS termination at ALB using ACM certificates
- No need for TLS certificates in Kubernetes
- Backend communication via HTTP (secure within VPC)
- External DNS automatically creates Route53 records
- Path-based routing directs requests to appropriate services:
  - `/api/v1/platform/*` → Platform Service (enterprise only)
  - `/login`, `/callback`, etc. → OAuth2 Service
  - All other paths → Web UI

:::warning Required Annotations for OAuth
When using OAuth2/OIDC authentication with ALB:
- **certificate-arn** is **REQUIRED** - Without it, the chart generates HTTP URLs instead of HTTPS, causing OAuth redirect URI mismatches
- **subnets** is **REQUIRED** - ALB needs to know which VPC subnets to use

See [HTTPS Auto-Detection and OAuth Requirements](#https-auto-detection-and-oauth-requirements) for details.
:::

**Health Endpoints:**
- Overall pod health: `https://sam.example.com/health` (webui service)
- Platform service health: `https://sam.example.com/api/v1/platform/health` (enterprise only)

---

### GKE Ingress (Google Cloud)

**Best for:** Google Kubernetes Engine (GKE) clusters

**Prerequisites:**
- GKE cluster with Ingress enabled
- Google-managed SSL certificate or cert-manager
- Static IP reserved (optional but recommended)

**Configuration:**

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # GKE Ingress handles TLS termination

ingress:
  enabled: true
  className: "gce"  # Google Cloud Ingress
  annotations:
    # Static IP (optional, recommended for production)
    kubernetes.io/ingress.global-static-ip-name: "sam-static-ip"

    # Google-managed SSL certificate
    networking.gke.io/managed-certificates: "sam-ssl-cert"

    # Or use cert-manager
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # Enable HTTPS redirect
    kubernetes.io/ingress.allow-http: "false"

    # Backend configuration (optional)
    cloud.google.com/backend-config: '{"default": "sam-backend-config"}'

  hosts:
    - host: sam.example.com  # Must specify host for GCE
      paths:
        # Auth endpoints → port 5050
        - path: /login
          pathType: Prefix
          portName: auth
        - path: /callback
          pathType: Prefix
          portName: auth
        - path: /refresh_token
          pathType: Prefix
          portName: auth
        - path: /user_info
          pathType: Prefix
          portName: auth
        - path: /exchange-code
          pathType: Prefix
          portName: auth
        - path: /is_token_valid
          pathType: Prefix
          portName: auth
        # Platform service API (enterprise only)
        # Health endpoint: /api/v1/platform/health
        - path: /api/v1/platform
          pathType: Prefix
          portName: platform
        # Web UI → port 80 (HTTP backend, TLS at Ingress)
        - path: /
          pathType: Prefix
          portName: webui

  # If using cert-manager instead of Google-managed certs
  tls: []
    # - secretName: sam-tls
    #   hosts:
    #     - sam.example.com
```

**Setup Steps:**

**1. Create a static IP (recommended):**
```bash
gcloud compute addresses create sam-static-ip --global
```

**2. Create a Google-managed SSL certificate:**
```bash
# Create ManagedCertificate resource
cat <<EOF | kubectl apply -f -
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: sam-ssl-cert
spec:
  domains:
    - sam.example.com
EOF
```

**3. (Optional) Create BackendConfig for custom settings:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: sam-backend-config
spec:
  healthCheck:
    checkIntervalSec: 15
    port: 80
    type: HTTP
    requestPath: /
  timeoutSec: 30
  connectionDraining:
    drainingTimeoutSec: 60
EOF
```

**4. Install SAM:**
```bash
helm install sam . -f values.yaml
```

**5. Get the Ingress IP:**
```bash
kubectl get ingress sam -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**6. Configure DNS:**
Create an A record pointing `sam.example.com` to the Ingress IP.

**Traffic Flow:**
```
Client (HTTPS)
   ↓
Google Cloud Load Balancer (TLS termination)
   ↓
HTTP (internal GCP network)
   ↓
GKE Service
   ↓
SAM Pods
```

**Key Points:**
- Google-managed certificates auto-renew
- Static IP recommended for production
- SSL certificate provisioning takes 15-30 minutes
- Uses Google Cloud Load Balancer (Global or Regional)

---

### Azure Application Gateway Ingress (AKS)

**Best for:** Azure Kubernetes Service (AKS) clusters

**Prerequisites:**
- AKS cluster with Application Gateway Ingress Controller (AGIC)
- Azure Application Gateway
- SSL certificate in Azure Key Vault or cert-manager
- Virtual Network configured

**Configuration:**

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # Application Gateway handles TLS termination

ingress:
  enabled: true
  className: "azure/application-gateway"
  annotations:
    # Application Gateway configuration
    appgw.ingress.kubernetes.io/backend-protocol: "http"
    appgw.ingress.kubernetes.io/ssl-redirect: "true"

    # Use SSL certificate from Azure Key Vault
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "sam-ssl-cert"

    # Or specify certificate by name
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # Health probe configuration
    appgw.ingress.kubernetes.io/health-probe-path: "/"
    appgw.ingress.kubernetes.io/health-probe-interval: "30"
    appgw.ingress.kubernetes.io/health-probe-timeout: "30"
    appgw.ingress.kubernetes.io/health-probe-unhealthy-threshold: "3"

    # Connection draining
    appgw.ingress.kubernetes.io/connection-draining: "true"
    appgw.ingress.kubernetes.io/connection-draining-timeout: "30"

    # Request timeout
    appgw.ingress.kubernetes.io/request-timeout: "30"

  hosts:
    - host: sam.example.com  # Must specify host
      paths:
        # Auth endpoints → port 5050
        - path: /login
          pathType: Prefix
          portName: auth
        - path: /callback
          pathType: Prefix
          portName: auth
        - path: /refresh_token
          pathType: Prefix
          portName: auth
        - path: /user_info
          pathType: Prefix
          portName: auth
        - path: /exchange-code
          pathType: Prefix
          portName: auth
        - path: /is_token_valid
          pathType: Prefix
          portName: auth
        # Platform service API (enterprise only)
        # Health endpoint: /api/v1/platform/health
        - path: /api/v1/platform
          pathType: Prefix
          portName: platform
        # Web UI → port 80 (HTTP backend, TLS at App Gateway)
        - path: /
          pathType: Prefix
          portName: webui

  # If using cert-manager
  tls: []
    # - secretName: sam-tls
    #   hosts:
    #     - sam.example.com
```

**Setup Steps:**

**1. Create Application Gateway (if not exists):**
```bash
az network application-gateway create \
  --name sam-appgw \
  --resource-group myResourceGroup \
  --location eastus \
  --capacity 2 \
  --sku Standard_v2 \
  --vnet-name myVNet \
  --subnet appgw-subnet \
  --public-ip-address sam-public-ip
```

**2. Install AGIC using Helm:**
```bash
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

helm install ingress-azure \
  application-gateway-kubernetes-ingress/ingress-azure \
  --namespace kube-system \
  --set appgw.subscriptionId=<subscription-id> \
  --set appgw.resourceGroup=<resource-group> \
  --set appgw.name=<appgw-name> \
  --set armAuth.type=servicePrincipal \
  --set armAuth.secretJSON=<secret-json>
```

**3. Upload SSL certificate to Azure Key Vault:**
```bash
# Create Key Vault
az keyvault create --name sam-keyvault --resource-group myResourceGroup

# Import certificate
az keyvault certificate import \
  --vault-name sam-keyvault \
  --name sam-ssl-cert \
  --file /path/to/certificate.pfx
```

**4. Configure Application Gateway to access Key Vault:**
```bash
# Enable managed identity on App Gateway
az network application-gateway identity assign \
  --gateway-name sam-appgw \
  --resource-group myResourceGroup \
  --identity sam-appgw-identity

# Grant access to Key Vault
az keyvault set-policy \
  --name sam-keyvault \
  --object-id <appgw-managed-identity-object-id> \
  --secret-permissions get \
  --certificate-permissions get
```

**5. Install SAM:**
```bash
helm install sam . -f values.yaml
```

**6. Get the Ingress IP:**
```bash
kubectl get ingress sam -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**7. Configure DNS:**
Create an A record in Azure DNS or your DNS provider pointing `sam.example.com` to the Application Gateway public IP.

**Traffic Flow:**
```
Client (HTTPS)
   ↓
Azure Application Gateway (TLS termination)
   ↓
HTTP (internal Azure VNet)
   ↓
AKS Service
   ↓
SAM Pods
```

**Key Points:**
- Application Gateway supports WAF (Web Application Firewall)
- SSL certificates managed in Azure Key Vault
- Integrated with Azure Monitor for observability
- Supports path-based and host-based routing
- Can integrate with Azure Front Door for global load balancing

---

### NGINX Ingress

**Best for:** Multi-cloud, on-premises, or when you need more control

**Prerequisites:**
- NGINX Ingress Controller installed
- TLS certificate (cert-manager recommended)

**Recommended Configuration (Automatic Paths):**

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # NGINX handles TLS termination

ingress:
  enabled: true
  className: "nginx"

  # Automatic path configuration (recommended)
  autoConfigurePaths: true
  host: "sam.example.com"

  annotations:
    # NGINX-specific settings
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"

    # Rate limiting (optional)
    nginx.ingress.kubernetes.io/limit-rps: "100"

    # Cert-manager (automatic TLS)
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

  # REQUIRED: TLS section triggers HTTPS URL generation
  tls:
    - secretName: sam-tls
      hosts:
        - sam.example.com
```

**Advanced Configuration (Manual Paths):**

<details>
<summary>Click to expand manual path configuration</summary>

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # NGINX handles TLS termination

ingress:
  enabled: true
  className: "nginx"

  # Manual path configuration
  autoConfigurePaths: false

  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/limit-rps: "100"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

  hosts:
    - host: sam.example.com
      paths:
        # Auth endpoints
        - path: /login
          pathType: Prefix
          portName: auth
        - path: /callback
          pathType: Prefix
          portName: auth
        - path: /is_token_valid
          pathType: Prefix
          portName: auth
        - path: /exchange-code
          pathType: Prefix
          portName: auth
        # Platform service API (enterprise only)
        - path: /api/v1/platform
          pathType: Prefix
          portName: platform
        # Web UI
        - path: /
          pathType: Prefix
          portName: webui

  tls:
    - secretName: sam-tls
      hosts:
        - sam.example.com
```

</details>


**With cert-manager (automatic TLS):**

Cert-manager will automatically provision and renew certificates from Let's Encrypt.

**Manual TLS certificate:**

```bash
# Create TLS secret manually
kubectl create secret tls sam-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  --namespace=<namespace>
```

---

### Other Ingress Controllers

SAM supports any Ingress controller that implements the Kubernetes Ingress specification:

- **Traefik**: Popular for microservices, automatic service discovery
- **HAProxy**: High performance, low latency
- **Contour** (Envoy): Modern, high performance
- **Kong**: API gateway features built-in
- **GCE Ingress**: Google Cloud native
- **Azure Application Gateway**: Azure native

See the [Kubernetes Ingress Controllers documentation](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) for more options.

---

## TLS/SSL Configuration

### When Using Ingress (Recommended)

**TLS termination happens at the Ingress/ALB level:**

```yaml
service:
  tls:
    enabled: false  # No service-level TLS needed

ingress:
  enabled: true
  # TLS handled by Ingress annotations or tls section
```

**Benefits:**
- No need to manage TLS certificates in Kubernetes (with ALB/ACM)
- Automatic certificate renewal (with cert-manager)
- Centralized TLS policy management
- Better performance (no double encryption)

### HTTPS Auto-Detection and OAuth Requirements

:::danger CRITICAL for OAuth/OIDC
When using OAuth2/OIDC authentication with Ingress, proper HTTPS configuration is **REQUIRED**. Missing TLS configuration will cause OAuth redirect URI mismatches and authentication failures.
:::

#### How the Chart Detects HTTPS

The chart automatically detects whether to use `https://` or `http://` URLs based on your configuration:

**For Ingress Mode** (when `ingress.enabled=true`):

HTTPS is detected if **either** condition is met:
1. **Standard Kubernetes TLS**: `ingress.tls` section has at least one entry
2. **ALB Certificate Annotation**: `alb.ingress.kubernetes.io/certificate-arn` annotation exists

**For Service Mode** (LoadBalancer/NodePort):

HTTPS is detected if: `service.tls.enabled=true`

#### URLs Affected by HTTPS Detection

When HTTPS is detected, these environment variables use `https://` scheme:
- `FRONTEND_SERVER_URL`
- `PLATFORM_SERVICE_URL`
- `OIDC_REDIRECT_URI` ← **Critical for OAuth!**
- `EXTERNAL_AUTH_CALLBACK`
- `EXTERNAL_AUTH_SERVICE_URL`
- `WEBUI_FRONTEND_SERVER_URL`
- `FRONTEND_REDIRECT_URL`

#### AWS ALB Configuration (OAuth Required)

```yaml
ingress:
  enabled: true
  className: "alb"
  annotations:
    # REQUIRED for HTTPS URL generation and OAuth
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:REGION:ACCOUNT:certificate/ID

    # REQUIRED for ALB subnet placement
    alb.ingress.kubernetes.io/subnets: subnet-xxx,subnet-yyy
```

**Why certificate-arn is required**:
- ✅ Triggers HTTPS URL generation in environment variables
- ✅ OAuth redirect URIs use `https://` (required by most OAuth providers)
- ✅ Prevents redirect URI mismatch errors

**Without certificate-arn**:
```yaml
# Generated URLs will be HTTP:
OIDC_REDIRECT_URI=http://sam.example.com/callback  ❌
# Azure AD/OAuth provider expects:
Configured redirect URI=https://sam.example.com/callback  ❌
# Result: OAuth authentication fails with "redirect_uri mismatch" error
```

**With certificate-arn**:
```yaml
# Generated URLs will be HTTPS:
OIDC_REDIRECT_URI=https://sam.example.com/callback  ✅
# Matches OAuth provider configuration:
Configured redirect URI=https://sam.example.com/callback  ✅
# Result: OAuth authentication succeeds
```

#### NGINX Ingress Configuration (OAuth Required)

```yaml
ingress:
  enabled: true
  className: "nginx"

  # REQUIRED: TLS section triggers HTTPS URL generation
  tls:
    - secretName: sam-tls  # Created by cert-manager or manually
      hosts:
        - sam.example.com
```

**Why tls section is required**:
- ✅ Triggers HTTPS URL generation
- ✅ OAuth redirect URIs use `https://`
- ✅ cert-manager can auto-provision Let's Encrypt certificates

#### Manual URL Override (Advanced)

If you need to override the auto-detected URLs:

```yaml
sam:
  frontendServerUrl: "https://custom-domain.com"  # Override frontend URL
  platformServiceUrl: "https://custom-platform.com"  # Override platform URL
```

**Use cases**:
- Custom domain different from ingress host
- Local development with port-forward
- Complex multi-ingress setups

### When Using LoadBalancer/NodePort

**TLS termination happens at the pod level.** You must provide a valid TLS certificate.

#### Option 1: Use an Existing Kubernetes TLS Secret (Recommended)

Create your TLS secret using your preferred method (cert-manager, external-secrets, manual, etc.):

```bash
kubectl create secret tls my-sam-tls \
  --cert=/path/to/tls.crt \
  --key=/path/to/tls.key \
  -n <namespace>
```

Then reference it in your values:

```yaml
service:
  type: LoadBalancer
  tls:
    enabled: true
    existingSecret: "my-sam-tls"

ingress:
  enabled: false
```

#### Option 2: Provide Certificates via --set-file

```yaml
service:
  type: LoadBalancer
  tls:
    enabled: true

ingress:
  enabled: false
```

**Install with certificates:**

```bash
helm install sam ./charts/solace-agent-mesh \
  -f values.yaml \
  --set-file service.tls.cert=/path/to/tls.crt \
  --set-file service.tls.key=/path/to/tls.key
```

#### Certificate Requirements

- Publicly trusted certificate (e.g., Let's Encrypt, commercial CA)
- Self-signed certificates are not supported
- Must match the hostname in `sam.dnsName`
- PEM format with full certificate chain

---

## Decision Matrix

| Scenario | Service Type | Ingress | Why |
|----------|--------------|---------|-----|
| **Local development** | ClusterIP | No | Use kubectl port-forward |
| **Team development** | NodePort | No | Quick team access without port-forward |
| **Simple cloud prod** | LoadBalancer | No | Quick setup |
| **Production (HTTP apps)** | ClusterIP | **Yes** ✅ | Cost-effective, scalable, feature-rich |
| **Bare-metal cluster** | NodePort or ClusterIP | Yes (with MetalLB) | No cloud provider available |
| **Multiple services** | ClusterIP | **Yes** ✅ | Share one load balancer |

---

## Examples

### Example 1: Development (Local)

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # No TLS for local development

ingress:
  enabled: false
```

**Access:**
```bash
# Port-forward both WebUI and Platform Service (use these specific ports for CORS)
kubectl port-forward svc/<release-name> 8000:80 8001:8001

# Visit http://localhost:8000
```

See [Local Development with Port-Forward](#local-development-with-port-forward) for why these specific ports are required.

---

### Example 2: Development (Team)

```yaml
service:
  type: NodePort

ingress:
  enabled: false
```

**Access:**
```bash
# Get node IP and port
kubectl get svc sam
# Visit https://<node-ip>:<nodeport>
```

---

### Example 3: Simple Production (AWS)

```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb-ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  tls:
    enabled: true

ingress:
  enabled: false
```

**Install:**
```bash
helm install sam . -f values.yaml \
  --set-file service.tls.cert=tls.crt \
  --set-file service.tls.key=tls.key
```

---

### Example 4: Production with AWS ALB

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # ALB handles TLS

ingress:
  enabled: true
  className: "alb"
  autoConfigurePaths: true  # Automatically configures all routes
  host: ""  # Empty for ALB
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/subnets: subnet-xxx,subnet-yyy
    external-dns.alpha.kubernetes.io/hostname: sam.example.com
```

---

### Example 5: Production with GKE Ingress

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # GKE handles TLS

ingress:
  enabled: true
  className: "gce"
  annotations:
    kubernetes.io/ingress.global-static-ip-name: "sam-static-ip"
    networking.gke.io/managed-certificates: "sam-ssl-cert"
  hosts:
    - host: sam.example.com
      paths:
          - path: /login
            pathType: Prefix
            portName: auth
          - path: /callback
            pathType: Prefix
            portName: auth
          - path: /refresh_token
            pathType: Prefix
            portName: auth
          - path: /user_info
            pathType: Prefix
            portName: auth
          - path: /exchange-code
            pathType: Prefix
            portName: auth
          - path: /is_token_valid
            pathType: Prefix
            portName: auth
          # Platform service (enterprise only)
          - path: /api/v1/platform
            pathType: Prefix
            portName: platform
          # Catch-all for Web UI → port 80 (HTTP, TLS at GKE)
          - path: /
            pathType: Prefix
            portName: webui
```

**Setup:**
```bash
# Create static IP
gcloud compute addresses create sam-static-ip --global

# Create managed certificate
kubectl apply -f - <<EOF
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: sam-ssl-cert
spec:
  domains:
    - sam.example.com
EOF

# Install SAM
helm install sam . -f values.yaml
```

---

### Example 6: Production with Azure Application Gateway (AKS)

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # App Gateway handles TLS

ingress:
  enabled: true
  className: "azure/application-gateway"
  annotations:
    appgw.ingress.kubernetes.io/backend-protocol: "http"
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "sam-ssl-cert"
  hosts:
    - host: sam.example.com
      paths:
          - path: /login
            pathType: Prefix
            portName: auth
          - path: /callback
            pathType: Prefix
            portName: auth
          - path: /refresh_token
            pathType: Prefix
            portName: auth
          - path: /user_info
            pathType: Prefix
            portName: auth
          - path: /exchange-code
            pathType: Prefix
            portName: auth
          - path: /is_token_valid
            pathType: Prefix
            portName: auth
          # Platform service (enterprise only)
          - path: /api/v1/platform
            pathType: Prefix
            portName: platform
          # Catch-all for Web UI → port 80 (HTTP, TLS at Azure App Gateway)
          - path: /
            pathType: Prefix
            portName: webui
```

**Setup:**
```bash
# Upload certificate to Key Vault
az keyvault certificate import \
  --vault-name sam-keyvault \
  --name sam-ssl-cert \
  --file certificate.pfx

# Install SAM
helm install sam . -f values.yaml
```

---

### Example 7: Production with NGINX + cert-manager

```yaml
service:
  type: ClusterIP
  tls:
    enabled: false  # NGINX handles TLS

ingress:
  enabled: true
  className: "nginx"
  autoConfigurePaths: true  # Automatically configures all routes
  host: "sam.example.com"
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: sam-tls
      hosts:
        - sam.example.com
```

---

## Platform Service Routing (Enterprise)

SAM Enterprise includes a Platform Service API for managing agents, deployments, connectors, and toolsets.

### Endpoints

All platform management endpoints are under the `/api/v1/platform` path:

- **Health**: `/api/v1/platform/health` - Service health check
- **Agents**: `/api/v1/platform/agents` - Agent management
- **Deployments**: `/api/v1/platform/deployments` - Deployment management
- **Connectors**: `/api/v1/platform/connectors` - Connector configuration
- **Toolsets**: `/api/v1/platform/toolsets` - Toolset management

### Ingress Configuration

**Important:** The `/api/v1/platform` path must be configured **before** any broader `/api` or `/api/v1` patterns in your ingress rules to ensure correct routing.

```yaml
paths:
  # Auth paths (specific)
  - path: /login
    pathType: Prefix
    portName: auth

  # Platform service (enterprise only - before broader /api patterns)
  - path: /api/v1/platform
    pathType: Prefix
    portName: platform

  # Webui catch-all (least specific, goes last)
  - path: /
    pathType: Prefix
    portName: webui
```

### Service Ports

- **HTTP**: Service port `8080` → Container port `8001`
- **HTTPS**: Service port `4443` → Container port `4443` (when service TLS enabled)

### Health Checks

The platform service provides its own health endpoint:

```bash
# Via ingress
curl https://sam.example.com/api/v1/platform/health

# Direct to service (within cluster)
curl http://sam:8080/api/v1/platform/health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "Platform Service"
}
```

---

## Additional Resources

- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/)
- [External DNS](https://github.com/kubernetes-sigs/external-dns)

---

## Support

For network configuration questions or issues, please open an issue in [GitHub Issues](https://github.com/SolaceProducts/solace-agent-mesh-helm-quickstart/issues).
