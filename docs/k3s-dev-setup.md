# k3s Dev-Environment Setup (WSL2)

## Prerequisites

- **WSL2** with 8-16 GB RAM
- **kubectl** and **helm** installed locally
- **Git** repository cloned

## Quick Start

```bash
cd datenplattform
chmod +x scripts/setup-k3s-dev.sh
./scripts/setup-k3s-dev.sh
```

That's it! Environment will be ready in 5-10 minutes.

---

## How It Works

The setup script does:

1. **Checks prerequisites** (kubectl, helm)
2. **Installs cert-manager** (for TLS certificate management)
3. **Installs ingress-nginx** (for Ingress routing)
4. **Updates Helm dependencies** (from Chart.yaml)
5. **Deploys Data Platform** with dev-optimized values (`ci/values-k3s-dev.yaml`)

---

## Dev Configuration

Dev-environment uses **reduced resources and single replicas**:

| Component | Production | Development |
|-----------|------------|-------------|
| PostgreSQL | Primary + Replica | Single Primary |
| Vault | 3 Replicas (HA) | 1 Replica |
| Keycloak | 2 Replicas + Infinispan | 1 Replica |
| MinIO | 4 Nodes (Distributed) | 1 Node (Standalone) |
| Superset | 2 Replicas | 1 Replica |
| Trino | 1 Coordinator + 3 Worker | 1 Coordinator + 1 Worker |

**All security features remain active:**
- ✅ RBAC policies
- ✅ NetworkPolicies (Deny-by-default)
- ✅ ExternalSecrets + Vault integration
- ✅ TLS on critical connections
- ✅ Security contexts (readOnlyRootFilesystem, runAsNonRoot)

Override file: `ci/values-k3s-dev.yaml`

---

## Accessing Services

### Option 1: Port Forwarding (Recommended)

```bash
# Forward Ingress traffic
kubectl port-forward svc/ingress-nginx 80:80 443:443 -n ingress-nginx

# Then access via:
# http://localhost/airflow
# http://localhost/bi
# http://localhost/catalog
# http://localhost/auth
```

### Option 2: Direct Port Forwarding

```bash
# Airflow
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080

# Superset
kubectl port-forward svc/data-platform-superset 8088:8088

# OpenMetadata
kubectl port-forward svc/data-platform-openmetadata 8585:8585

# Keycloak
kubectl port-forward svc/data-platform-keycloak 8080:8080
```

### Option 3: kubectl describe

Get pod IPs:
```bash
kubectl get pods -o wide
```

---

## Monitoring

### Check Pod Status

```bash
kubectl get pods
kubectl get pods -w  # Watch mode
```

### View Logs

```bash
kubectl logs <pod-name>
kubectl logs <pod-name> -f  # Follow

# Example:
kubectl logs data-platform-airflow-scheduler -f
```

### Resource Usage

```bash
kubectl top pods
kubectl top nodes
```

### Describe Pod (debug)

```bash
kubectl describe pod <pod-name>
kubectl describe pvc <pvc-name>
```

---

## Verification

### Run Tests

```bash
helm test data-platform --timeout 5m
```

Tests verify:
- PostgreSQL connectivity
- MinIO reachability
- Trino availability
- Keycloak health
- Vault health

### Manual Verification

```bash
# Check all services are running
kubectl get svc

# Check persistent volumes
kubectl get pvc

# Check network policies
kubectl get networkpolicies

# Verify secrets are synced (ExternalSecrets)
kubectl get externalSecrets
kubectl get secrets
```

---

## Configuration Changes

### Increase Resources (if out of memory)

Edit `ci/values-k3s-dev.yaml`:

```yaml
airflow:
  scheduler:
    resources:
      requests: { cpu: 500m, memory: 1Gi }  # Increase from 250m/512Mi
      limits: { cpu: 1000m, memory: 2Gi }
```

Then redeploy:
```bash
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --wait --timeout 15m
```

### Increase WSL2 Memory

Edit `.wslconfig` in Windows home directory:

```ini
[wsl2]
memory=16GB
processors=4
swap=2GB
```

Then restart WSL2:
```powershell
wsl --shutdown
```

---

## Cleanup

### Remove Data Platform

```bash
helm uninstall data-platform
helm uninstall cert-manager -n cert-manager
helm uninstall ingress-nginx -n ingress-nginx
```

### Full Reset (WARNING: Deletes k3s)

```bash
# On WSL2:
k3s-uninstall.sh

# Or reinstall:
curl -sfL https://get.k3s.io | sh -
```

---

## Troubleshooting

### "Pod stuck in Pending"

```bash
kubectl describe pod <pod-name>
# Check events section for reason
```

**Common causes:**
- Storage provisioning timeout (wait, or reduce storage size in `ci/values-k3s-dev.yaml`)
- Resource limits exceeded (increase WSL2 memory)
- Image pull failure (check `kubectl logs` for details)

### "ImagePullBackOff"

Check if image registry is accessible:
```bash
kubectl describe pod <pod-name>
# Look at Image field and pull errors
```

### "Out of Memory" (OOMKilled)

Pods were killed due to memory pressure:
```bash
# Check which pod
kubectl describe pod <pod-name> | grep -i memory

# Increase WSL2 memory (see Configuration section)
# OR reduce replicas/resources in ci/values-k3s-dev.yaml
```

### "Helm timeout"

Deployment taking too long (normal on WSL2):
```bash
# Increase timeout
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --timeout 20m
```

Or watch progress:
```bash
kubectl get pods -w
# Wait for all pods to be Running/Ready
```

### "ExternalSecrets not syncing"

Check Vault is accessible and unsealed:
```bash
kubectl get externalSecrets
kubectl describe externalsecret <secret-name>
```

If stuck: Vault may be sealed. Manual unseal needed (production process, not in dev).

### "Network connectivity issues"

Check NetworkPolicies are not too strict:
```bash
kubectl get networkpolicies
kubectl describe networkpolicy <policy-name>
```

For debugging: Temporarily disable NetworkPolicies:
```yaml
networkPolicies:
  enabled: false
```

---

## Performance Notes

⚠️ **k3s on WSL2 is not production-representative:**
- Storage I/O slower than real Kubernetes
- Network latency higher than bare metal
- Some operations take 2-3x longer (normal, expected)

**Use for:**
- ✅ Development and testing
- ✅ Feature validation
- ✅ Integration testing
- ✅ YAML syntax/linting

**NOT for:**
- ❌ Performance testing
- ❌ Load testing
- ❌ Production-like deployment validation

---

## Resources

- **Main docs:** `docs/architecture.md`, `docs/networking.md`, `docs/operations.md`
- **Setup guides:** `docs/keycloak-setup.md`, `docs/metabase-setup.md`
- **Security:** `CLAUDE.md`, `docs/adrs/`
- **Testing:** `scripts/validate.sh`, `helm test`

---

## Getting Help

1. Check `docs/operations.md` for common issues
2. Read `CLAUDE.md` for architecture decisions
3. Run `helm test data-platform` to verify installation
4. Check pod logs: `kubectl logs <pod-name>`
5. Ask team or check GitHub issues
