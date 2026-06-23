# Installation & Deployment Guide

Production-ready deployment of the Data Platform Helm Chart on Kubernetes.

---

## Overview

This guide covers deploying the complete Data Platform on a Kubernetes cluster (1.32+).

**Version**: v1.1+ with **Multi-Namespace Architecture** (7 isolated namespaces instead of single-namespace)
- See `docs/MULTI-NAMESPACE-REFACTOR-SUMMARY.md` for details
- Service discovery via FQDN (e.g., `postgresql.data-storage.svc.cluster.local`)
- Deny-by-default NetworkPolicies per namespace

For local development, see:
- **k3s Dev**: `docs/k3s-dev-setup.md` (automated cluster setup)
- **Engineer Dev**: `docs/engineer-dev-setup.md`
- **Analyst Dev**: `docs/analyst-dev-setup.md`

---

## Prerequisites

### Kubernetes Cluster
- Kubernetes 1.32+
- kubeconfig configured and working
- Sufficient resources (minimum 16 GB RAM, 8 CPUs for single-node; more for HA)

### Infrastructure
- **Ingress Controller** (e.g., ingress-nginx) with TLS termination
- **cert-manager** for automatic TLS certificate management
- **StorageClass** with ReadWriteOnce support (e.g., `standard`, `gp3`)

### Tools
```bash
# Required
helm 3.19+
kubectl 1.32+
git

# Optional (recommended)
trivy              # for security scanning
helm-unittest      # for test validation
```

### DNS & Networking
- Domain name pointing to your cluster (e.g., `data-platform.example.com`)
- Wildcard DNS or individual A records for each service
- Network policies enabled (or can be enabled later)

---

## Step 1: Clone & Prepare Repository

```bash
git clone https://github.com/askrason/datenplattform.git
cd datenplattform

# Verify structure
ls -la
# → Chart.yaml, values.yaml, CLAUDE.md, docs/, scripts/, templates/, etc.
```

---

## Step 2: Review Configuration

### Read CLAUDE.md
```bash
# Must read - contains:
# - ADRs (Architecture Decision Records)
# - Security Baseline (NON-NEGOTIABLE)
# - Known Issues (especially #6 Bitnami OCI migration)
cat CLAUDE.md | head -100
```

### Check Known Issues
Pay special attention to:
- **Known Issue #6**: Bitnami OCI migration (PostgreSQL, Keycloak image tags)
- **Known Issue #7**: Multi-Namespace Architecture (v1.1+) – Service discovery via FQDN required
- **Known Issue #8**: Dev-profile secrets (only for local clusters)

### Customize values.yaml

```bash
vim values.yaml
```

Update these critical values:

```yaml
global:
  domain: "data-platform.example.com"    # Your domain
  storageClass: "standard"                # Or your cloud provider's class
  imageRegistry: "docker.io"              # Can use private registry
  imagePullPolicy: IfNotPresent           # Good for air-gapped
  # imagePullSecrets:                     # If using private registry
  #   - name: regcred

vault:
  enabled: true                           # Always true for production

keycloak:
  enabled: true                           # Always true for production

# Others: Keep defaults or customize per your needs
```

---

## Step 3: Prepare Kubernetes Cluster

### Create Namespace
```bash
kubectl create namespace data-platform
# Or use --namespace in helm install
```

### Install Ingress Controller (if not present)
```bash
# Example: ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --values - << 'EOF'
controller:
  service:
    type: LoadBalancer  # or NodePort for on-prem
  metrics:
    enabled: true
EOF
```

### Install cert-manager (if not present)
```bash
# CertManager for automatic TLS
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
```

### Install External Secrets Operator (if not present)
```bash
# ESO is installed as a Helm dependency, but can pre-install if preferred
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

---

## Step 4: Prepare Helm Dependencies

```bash
# Update Helm repository indexes
helm repo add vault https://helm.releases.hashicorp.com
helm repo add apache https://airflow.apache.org
helm repo add trinodb https://trinodb.github.io/charts
helm repo add open-metadata https://helm.open-metadata.org
helm repo add apache-superset https://apache.github.io/superset
helm repo update

# Download chart dependencies
helm dependency update

# Verify dependencies downloaded
ls -la charts/
```

---

## Step 5: Pre-Deployment Validation

```bash
# Validate chart syntax
./scripts/validate.sh

# Template rendering (dry-run)
helm template data-platform . \
  --values values.yaml \
  --output-dir /tmp/rendered

# Check for obvious issues
kubectl apply --dry-run=client -f /tmp/rendered/data-platform/templates/ 2>&1 | head -20
```

---

## Step 6: Initialize Vault (Critical!)

**BEFORE deploying the chart**, Vault must be initialized and unsealed.

### Option A: Vault Auto Unseal (Cloud KMS)
Recommended for production. Configure in `values/vault.yaml`:

```yaml
vault:
  server:
    ha:
      enabled: true
    config: |
      seal "awskms" {
        region = "us-east-1"
        kms_key_id = "arn:aws:kms:..."
      }
      # ... rest of config
```

### Option B: Manual Unseal (Shamir)
```bash
# After chart deployment (see Step 7), manually unseal:
kubectl port-forward svc/data-platform-vault 8200:8200 &

# In another terminal:
vault operator init -key-shares=5 -key-threshold=3
# Save the unseal keys and root token SECURELY

vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>

# Check status:
vault status
```

Store unseal keys and root token in a **secure vault** (e.g., encrypted password manager, Bitwarden, 1Password).

---

## Step 7: Deploy the Chart

### Standard Deployment (Production)

```bash
helm install data-platform . \
  --namespace data-platform \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 20m
```

### With Custom Domain

```bash
helm install data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --set global.domain="your-domain.com" \
  --wait \
  --timeout 20m
```

### With Private Image Registry

```bash
# Create image pull secret first
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --namespace data-platform

# Then install with:
helm install data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --set global.imagePullSecrets[0].name=regcred \
  --wait
```

---

## Step 8: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n data-platform

# Check services
kubectl get svc -n data-platform

# Check ingress
kubectl get ingress -n data-platform

# Check that ingress has external IP
kubectl get ingress -n data-platform -o wide
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS
data-platform-vault-0                   1/1     Running   0
data-platform-postgresql-0              1/1     Running   0
data-platform-minio-0                   1/1     Running   0
data-platform-airflow-scheduler-xxx     1/1     Running   0
data-platform-airflow-webserver-xxx     1/1     Running   0
...
```

---

## Step 9: Initialize Keycloak

```bash
# Port-forward to Keycloak
kubectl port-forward svc/data-platform-keycloak 8080:80 -n data-platform &

# Access admin console:
# http://localhost:8080/admin

# Default credentials (from values/keycloak.yaml):
# Username: admin
# Password: changeme (UPDATE in values!)

# Import Realm
# - Go to Administration → Realms → Import
# - Upload: files/keycloak-realm.json
# - Click Import
```

Or via CLI:
```bash
# Export current realm
kubectl exec data-platform-keycloak-0 -n data-platform -- \
  /opt/keycloak/bin/kc.sh export \
  --realm master \
  --dir /tmp

# Import realm
kubectl exec data-platform-keycloak-0 -n data-platform -- \
  /opt/keycloak/bin/kc.sh import \
  --realm-dir /tmp
```

---

## Step 10: Initialize PostgreSQL

```bash
# Check PostgreSQL is accessible
kubectl exec -it data-platform-postgresql-0 -n data-platform -- \
  psql -U postgres -c "\l"

# Expected databases: postgres, airflow, metabase, superset, openmetadata

# If databases missing, create them:
kubectl exec -it data-platform-postgresql-0 -n data-platform -- psql -U postgres << 'EOF'
CREATE DATABASE airflow;
CREATE DATABASE metabase;
CREATE DATABASE superset;
CREATE DATABASE openmetadata;
EOF
```

---

## Step 11: Configure DNS & TLS

### Add DNS Records

```bash
# Get Ingress external IP
kubectl get ingress -n data-platform -o wide

# Create A records (or CNAME)
# In your DNS provider:
# data-platform.example.com       → <EXTERNAL-IP>
# airflow.example.com             → <EXTERNAL-IP>
# superset.example.com            → <EXTERNAL-IP>
# metabase.example.com            → <EXTERNAL-IP>
# openmetadata.example.com        → <EXTERNAL-IP>
# vault.example.com               → <EXTERNAL-IP> (or internal-only)
# keycloak.example.com            → <EXTERNAL-IP>
```

### Check TLS Certificates

```bash
# cert-manager should automatically create certificates
kubectl get certificate -n data-platform

# Check certificate status
kubectl describe certificate data-platform-tls -n data-platform

# Expected: Certificate is valid for *.example.com
```

---

## Step 12: Access the Platform

Once DNS + TLS are ready:

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Airflow | https://airflow.example.com | admin / airflow |
| Superset | https://superset.example.com | admin / admin |
| Metabase | https://metabase.example.com | admin@example.com / (via OAuth) |
| OpenMetadata | https://openmetadata.example.com | admin / admin |
| Keycloak | https://keycloak.example.com/admin | admin / changeme |
| Vault | https://vault.example.com | root token |
| MinIO Console | https://minio.example.com | minioadmin / minioadmin |

**Change default passwords immediately!**

---

## Troubleshooting

### Pods stuck in CreateContainerConfigError

```bash
# Check if secrets exist
kubectl get secret -n data-platform

# Check pod events
kubectl describe pod <pod-name> -n data-platform

# Missing secret likely - check ExternalSecrets
kubectl get externalsecret -n data-platform
kubectl describe externalsecret <name> -n data-platform

# Verify Vault connectivity
kubectl logs -n data-platform -l app.kubernetes.io/name=external-secrets
```

### Ingress not working

```bash
# Check ingress status
kubectl describe ingress data-platform-airflow -n data-platform

# Check DNS
nslookup airflow.example.com

# Test from pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n data-platform -- \
  curl -v https://airflow.example.com/health
```

### Vault issues

```bash
# Check Vault status
kubectl exec data-platform-vault-0 -n data-platform -- vault status

# Check Vault logs
kubectl logs data-platform-vault-0 -n data-platform

# If unsealed required
kubectl port-forward svc/data-platform-vault 8200:8200 -n data-platform
vault operator unseal <key>
```

---

## Post-Deployment Tasks

1. **Change default passwords**
   - Keycloak admin
   - PostgreSQL users
   - MinIO credentials

2. **Configure SMTP** (for notifications)
   - Airflow
   - Superset
   - OpenMetadata

3. **Set up backups**
   - PostgreSQL
   - MinIO buckets
   - Vault data

4. **Enable monitoring**
   - Prometheus (optional)
   - Grafana (optional)
   - Logs aggregation

5. **Load container images** (if air-gapped)
   - See `docs/image-management.md`
   - Run `./scripts/load-container-images.sh`

6. **Run validation**
   ```bash
   ./scripts/validate.sh
   ```

---

## Upgrades

```bash
# Update chart version in Chart.yaml
vim Chart.yaml

# Update dependencies
helm dependency update

# Dry-run upgrade
helm upgrade data-platform . \
  --dry-run \
  --debug \
  --namespace data-platform \
  --values values.yaml

# Actually upgrade
helm upgrade data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --wait
```

---

## Uninstall

**WARNING:** This deletes all deployments but keeps PVCs.

```bash
# Delete chart
helm uninstall data-platform -n data-platform

# Keep namespace and PVCs for restore later
# Or delete everything:
kubectl delete namespace data-platform  # ⚠️ DATA LOSS
```

---

## See Also

- **Security**: CLAUDE.md, `docs/security-scanning.md`
- **Troubleshooting**: `docs/operations.md`
- **Architecture**: `docs/architecture.md`
- **Dev Deployment**: `docs/k3s-dev-setup.md`
- **Air-Gapped**: `docs/offline-deployment.md`
