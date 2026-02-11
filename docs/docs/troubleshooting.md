---
sidebar_position: 3
title: Troubleshooting
---

# Troubleshooting SAM Deployments

This guide provides solutions for common issues when deploying and running Solace Agent Mesh (SAM).

## Diagnostic Commands

**Note:** The commands below use `app.kubernetes.io/instance=agent-mesh` where `agent-mesh` is the Helm release name. Replace `agent-mesh` with your actual release name if different.

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/instance=agent-mesh
```

### View Pod Logs

```bash
kubectl logs -l app.kubernetes.io/instance=agent-mesh --tail=100 -f
```

### Check ConfigMaps

```bash
kubectl get configmaps -l app.kubernetes.io/instance=agent-mesh
```

### Check Secrets

```bash
kubectl get secrets -l app.kubernetes.io/instance=agent-mesh
```

### Verify Service

```bash
kubectl get service -l app.kubernetes.io/instance=agent-mesh
```

## Common Issues

### Pod fails to start

- Check that the image is accessible
- Verify resource limits are sufficient
- Review pod events: `kubectl describe pod <pod-name>`

### Cannot connect to Solace broker

- Verify `solaceBroker.url` is correct and reachable
- Check credentials in `solaceBroker.username` and `solaceBroker.password`
- Ensure the VPN name is correct

### TLS issues

- Verify certificate and key are properly formatted
- Check certificate expiration
- Ensure certificate matches the hostname

### Database connection issues

- Verify database URLs are correct
- Check database credentials
- Ensure databases exist and are accessible from the cluster

### Helm upgrade fails with StatefulSet forbidden error

**Symptoms**: Helm upgrade fails with error about StatefulSet spec updates being forbidden:

```
StatefulSet.apps "xxx-postgresql" is invalid: spec: Forbidden: updates to statefulset spec
for fields other than 'replicas', 'ordinals', 'template', 'updateStrategy'... are forbidden
```

**Cause**: This occurs when upgrading bundled persistence deployments from chart version ≤1.1.0. Kubernetes StatefulSet VolumeClaimTemplate labels are immutable, and newer chart versions use different labels.

**Solution**: Follow the migration procedure in [Bundled Persistence VCT Labels](/#bundled-persistence-vct-labels-upgrading-from-110):

```bash
# Step 1: Delete StatefulSets while preserving PVCs
kubectl delete sts <release>-postgresql <release>-seaweedfs --cascade=orphan -n <namespace>

# Step 2: Upgrade the Helm release
helm upgrade <release> solace-agent-mesh/solace-agent-mesh -f your-values.yaml -n <namespace>
```

Your data is preserved - the new StatefulSets automatically reattach to existing PVCs.

### Insufficient node disk space

**Symptoms**: Image pull fails with "no space left on device" error:

```
Warning  Failed  kubelet  Failed to pull image "gcr.io/gcp-maas-prod/solace-agent-mesh-enterprise:x.x.x":
failed to pull and unpack image: failed to extract layer: write ... no space left on device: unknown
```

**Cause**: SAM requires pulling several container images. Nodes with insufficient disk space cannot store all required images.

**Solution**:

1. Ensure nodes have at least **30 GB** of disk space

2. If using managed Kubernetes, resize your node pool's disk size or create a new node pool with larger disks

### Platform Service Not Accessible (Ingress)

**Symptoms**:
- Cannot access `/api/v1/platform/*` endpoints
- 404 errors when trying to access platform APIs
- Enterprise features (agent builder, deployments, connectors) not working

**Diagnosis**:

1. Check if platform routes are configured in Ingress:
   ```bash
   kubectl get ingress <release-name> -n <namespace> -o yaml | grep -A 5 "/api/v1/platform"
   ```

2. Verify platform service is running:
   ```bash
   kubectl get svc <release-name> -n <namespace> -o yaml | grep "platform"
   ```

3. Check platform service health:
   ```bash
   # Via ingress
   curl -k https://sam.example.com/api/v1/platform/health

   # Direct to service (from within cluster)
   kubectl run -i --tty --rm debug --image=curlimages/curl --restart=Never -- \
     curl http://<release-name>:8080/api/v1/platform/health
   ```

**Solution**:

- **Recommended**: Enable automatic path configuration (default in new installations):
  ```yaml
  ingress:
    autoConfigurePaths: true
  ```

- **If using manual paths** (`autoConfigurePaths: false`), add platform route before catch-all:
  ```yaml
  ingress:
    autoConfigurePaths: false
    hosts:
      - host: "sam.example.com"
        paths:
          # Platform route MUST be before /* catch-all
          - path: /api/v1/platform
            pathType: Prefix
            portName: platform
          - path: /
            pathType: Prefix
            portName: webui
  ```

- **Upgrade**: Run helm upgrade with your existing values:
  ```bash
  helm upgrade <release-name> solace-agent-mesh/solace-agent-mesh \
    -f your-values.yaml \
    -n <namespace>
  ```

### Platform Service Not Accessible (LoadBalancer)

**Symptoms**:
- Platform API not accessible on port 4443 (HTTPS) or 8080 (HTTP)
- Enterprise features not working despite WebUI being accessible

**Diagnosis**:

1. Check LoadBalancer ports:
   ```bash
   kubectl get svc <release-name> -n <namespace> -o yaml | grep -A 2 "platform"
   ```

2. Verify external IP:
   ```bash
   kubectl get svc <release-name> -n <namespace> -o wide
   ```

3. Test platform API access:
   ```bash
   # HTTPS (if service.tls.enabled: true)
   curl -k https://<EXTERNAL-IP>:4443/api/v1/platform/health

   # HTTP (if service.tls.enabled: false)
   curl http://<EXTERNAL-IP>:8080/api/v1/platform/health
   ```

**Solution**:

Platform API is exposed on **separate ports** from WebUI:

**With TLS enabled** (`service.tls.enabled: true`):
- Web UI: `https://<EXTERNAL-IP>` (port 443)
- Platform API: `https://<EXTERNAL-IP>:4443`

**Without TLS** (`service.tls.enabled: false`):
- Web UI: `http://<EXTERNAL-IP>` (port 80)
- Platform API: `http://<EXTERNAL-IP>:8080`

If platform ports are not exposed, upgrade your deployment:
```bash
helm upgrade <release-name> solace-agent-mesh/solace-agent-mesh \
  -f your-values.yaml \
  -n <namespace>
```

### CORS Errors in Local Development

**Symptoms**:
- Browser console shows CORS errors: `Access-Control-Allow-Origin`
- Platform API calls fail with network errors
- Enterprise features (agent builder, deployments) not working
- WebUI loads but buttons/features don't respond

**Diagnosis**:

1. Open browser developer tools (F12) and check the Console tab for errors like:
   ```
   Access to fetch at 'http://localhost:XXXXX/api/v1/platform/...'
   from origin 'http://localhost:YYYY' has been blocked by CORS policy
   ```

2. Verify you're using the correct ports:
   ```bash
   # Correct - uses pre-configured CORS ports
   kubectl port-forward svc/<release-name> 8000:80 8001:8001
   ```

**Common Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| Using `minikube service` (random ports) | Use `local-k8s-values.yaml` sample, or switch to port 8000 |
| Using non-standard port (e.g., 9000:80) | Use `local-k8s-values.yaml` sample, or switch to port 8000 |
| Missing Platform Service port-forward | Add `8001:8001` to your port-forward command |

**Solution A: Use the local development sample file (Recommended)**

The `local-k8s-values.yaml` sample includes CORS configuration that allows any localhost port:
```bash
helm install agent-mesh solace-agent-mesh/solace-agent-mesh -f local-k8s-values.yaml
```

**Solution B: Use specific ports**

If not using the sample file, use port 8000 (pre-configured in CORS):
```bash
kubectl port-forward -n <namespace> svc/<release-name> 8000:80 8001:8001
```

**Pre-configured CORS origins (without the sample file):**
- `http://localhost:8000` ✅
- `http://localhost:3000` ✅
- Other ports ❌ (blocked by CORS)

For more details, see [Network Configuration - Local Development](network-configuration#local-development-with-port-forward).

## Getting Help

For issues, questions, or contributions, please open an issue in [GitHub Issues](https://github.com/SolaceProducts/solace-agent-mesh-helm-quickstart/issues).
