# Data Engineer Dev-Environment Setup

## Overview

Quick local development environment for **DAG/dbt development**.

- **Components:** Airflow, Trino, PostgreSQL, MinIO
- **NOT included:** Vault, Keycloak, OpenMetadata (security not relevant for DAG dev)
- **Resources:** 4-6 GB RAM
- **Setup time:** 3-4 minutes

## Quick Start

```bash
cd datenplattform
chmod +x scripts/setup-engineer-dev.sh
./scripts/setup-engineer-dev.sh
```

## What's Included

| Component | Purpose | Notes |
|-----------|---------|-------|
| **Airflow** | DAG orchestration + scheduling | Focus of this environment |
| **Trino** | Query engine for testing queries | Minimal 1-worker setup |
| **PostgreSQL** | Data warehouse + Airflow metastore | Single replica |
| **MinIO** | S3-compatible object store for DAG artifacts | Standalone mode |

## Accessing Services

### Airflow Webserver

```bash
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080
# Then: http://localhost:8080
```

**Login:** airflow / airflow (default)

### Trino UI

```bash
kubectl port-forward svc/data-platform-trino 8080:8080
# Then: http://localhost:8080/ui/
```

## Common Tasks

### Create/Deploy a DAG

```bash
# Find Airflow scheduler pod
kubectl get pods | grep airflow-scheduler

# Copy DAG file
kubectl cp my_dag.py <pod-name>:/opt/airflow/dags/

# Or use volume mount if dags-pvc exists
kubectl get pvc | grep airflow
```

### Test a Query in Trino

```bash
kubectl port-forward svc/data-platform-trino 8080:8080

# Then visit http://localhost:8080/ui/
# Or use trino CLI:
trino --server http://localhost:8080 --catalog minio --schema default
```

### Check PostgreSQL

```bash
kubectl exec -it data-platform-postgresql-0 -- psql -U postgres -d airflow
```

### View MinIO

```bash
kubectl port-forward svc/data-platform-minio 9001:9001
# Console: http://localhost:9001 (credentials from env/logs)
```

## Monitoring

```bash
# Pod status
kubectl get pods -w

# Logs
kubectl logs <pod-name> -f

# Resource usage
kubectl top pods
```

## Cleanup

```bash
# Remove deployment
helm uninstall data-platform

# Remove persistent data
kubectl delete pvc --all
```

## Important Notes

⚠️ **NOT Production-Ready:**
- No Vault/Keycloak = no authentication/secrets management
- No OpenMetadata = no data governance
- Single replicas = no HA
- For production-like testing, use `values-k3s-dev.yaml`

✅ **Good for:**
- DAG/dbt development and testing
- Query development
- Local iteration
- Testing Airflow jobs before pushing

## Troubleshooting

### Pod won't start

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Out of memory

Increase WSL2 memory:
```ini
# .wslconfig
[wsl2]
memory=8GB
```

### Helm timeout

```bash
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --timeout 15m
```

## See Also

- Full-stack dev: `docs/k3s-dev-setup.md`
- Analyst-only setup: `docs/analyst-dev-setup.md`
- Architecture: `docs/architecture.md`
