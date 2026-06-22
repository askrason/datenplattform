# Development Secrets Bootstrap Guide

For local development environments without Vault (TICKET-014: Engineer, TICKET-015: Analyst).

---

## Why Bootstrap Script?

When `vault.enabled: false` and `external-secrets.enabled: false`, the chart expects Kubernetes Secrets at:
- `data-platform-postgresql-credentials`
- `data-platform-airflow-db-credentials`
- `data-platform-minio-credentials`
- `data-platform-trino-credentials`
- `data-platform-superset-db-credentials` (analyst)
- `data-platform-metabase-db-credentials` (analyst)

Without these, pods hang in `CreateContainerConfigError`.

**Solution:** `scripts/bootstrap-dev-secrets.sh` generates random passwords and creates Secrets via `kubectl`.

---

## Quick Start

### Engineer Profile

```bash
# 1. Start your cluster
k3s  # or minikube start, kind create cluster, etc.

# 2. Create secrets
./scripts/bootstrap-dev-secrets.sh engineer

# 3. Deploy
helm install data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml
```

### Analyst Profile

```bash
./scripts/bootstrap-dev-secrets.sh analyst

helm install data-platform . \
  --values values.yaml \
  --values ci/values-analyst-dev.yaml
```

---

## What Gets Created

### Engineer Secrets

```
data-platform-postgresql-credentials
  username: postgres
  password: <random>

data-platform-airflow-db-credentials
  username: airflow
  password: <random>

data-platform-airflow-oidc-credentials
  client_id: airflow-dev
  client_secret: dev-stub-secret-no-keycloak

data-platform-minio-credentials
  rootUser: minioadmin
  rootPassword: <random>

data-platform-trino-credentials
  username: admin
  password: <random>
```

### Analyst Secrets

```
data-platform-postgresql-credentials
  username: postgres
  password: <random>

data-platform-trino-credentials
  username: admin
  password: <random>

data-platform-superset-db-credentials
  username: superset
  password: <random>

data-platform-metabase-db-credentials
  username: metabase
  password: <random>
```

---

## Important Notes

### ✅ Acceptable Use

- Local development only (ephemeral k3s/minikube clusters)
- Temporary, never committed to git
- Different from production secret management

### ❌ NEVER Use For

- Shared clusters
- Production deployments
- Multi-user systems

---

## Clearing Secrets

When tearing down the cluster:

```bash
# Remove individual secrets
kubectl delete secret data-platform-postgresql-credentials
kubectl delete secret data-platform-airflow-db-credentials
# ... etc

# Or remove all at once
kubectl delete secret -l app.kubernetes.io/instance=data-platform

# Or delete entire cluster
k3s server --disable=servicelb  # stop k3s
# ... or minikube delete, kind delete cluster, etc.
```

---

## Troubleshooting

### "Secret already exists"

```bash
# Secrets are idempotent-safe. Script will skip if already present.
# To regenerate:
kubectl delete secret data-platform-postgresql-credentials
./scripts/bootstrap-dev-secrets.sh engineer
```

### "kubectl: command not found"

```bash
# Install kubectl or configure your shell to use k3s' bundled version:
export PATH=/usr/local/bin:$PATH  # k3s installs here
which kubectl
```

### "Not connected to a Kubernetes cluster"

```bash
# Start your cluster:
k3s  # or:
minikube start
# or:
kind create cluster --config ci/kind-config.yaml
```

### Pods still in CreateContainerConfigError

```bash
# Check which secrets are missing:
kubectl get pods -o wide
kubectl describe pod <pod-name>

# See logs:
kubectl logs <pod-name>

# Re-run bootstrap:
./scripts/bootstrap-dev-secrets.sh engineer
```

---

## See Also

- **Engineer Setup**: `docs/engineer-dev-setup.md`
- **Analyst Setup**: `docs/analyst-dev-setup.md`
- **Full-Stack Setup**: `docs/k3s-dev-setup.md`
- **Security Note**: CLAUDE.md, Known Issue #7
