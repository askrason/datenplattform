# Data Analyst Dev-Environment Setup

## Overview

Quick local development environment for **Query and BI development**.

- **Components:** Trino, Superset, Metabase, PostgreSQL
- **NOT included:** Vault, Keycloak, Airflow, OpenMetadata (not relevant for BI dev)
- **Resources:** 6-8 GB RAM
- **Setup time:** 4-5 minutes

## Quick Start

```bash
cd datenplattform
chmod +x scripts/setup-analyst-dev.sh
./scripts/setup-analyst-dev.sh
```

## What's Included

| Component | Purpose | Notes |
|-----------|---------|-------|
| **Trino** | Distributed SQL query engine | Focus of this environment |
| **Superset** | Primary BI tool for dashboards | Apache Superset with native Trino support |
| **Metabase** | Secondary BI tool (self-service analytics) | Community edition, lightweight |
| **PostgreSQL** | Data warehouse (sample data) | Single replica |

## Accessing Services

### Trino UI

```bash
kubectl port-forward svc/data-platform-trino 8080:8080
# Then: http://localhost:8080/ui/
```

**Access:** No auth required

### Superset

```bash
kubectl port-forward svc/data-platform-superset 8088:8088
# Then: http://localhost:8088
```

**Login:** admin / admin (default)

**Setup:**
1. Add Trino as database connection
2. Create datasets from queries
3. Build dashboards

### Metabase

```bash
kubectl port-forward svc/data-platform-metabase 3000:3000
# Then: http://localhost:3000
```

**First login:** Follow setup wizard
- Add database: Trino
- Create questions/dashboards

## Common Tasks

### Test a Trino Query

**Option 1: Trino UI**
```
http://localhost:8080/ui/
```

**Option 2: CLI**
```bash
# Install trino CLI
trino --server http://localhost:8080 --catalog minio --schema default

> SELECT * FROM my_table LIMIT 5;
```

### Create a Dashboard in Superset

1. Port-forward to Superset
2. Login with admin/admin
3. Add Trino database:
   - Host: `data-platform-trino` (if accessing from pod)
   - Or `localhost:8080` (if port-forwarding)
4. Create dataset from SQL query
5. Create visualization
6. Add to dashboard

### Create a Report in Metabase

1. Port-forward to Metabase
2. Add Trino database via setup wizard
3. Create a "New question"
4. Write SQL or use query builder
5. Save and share

### Check Available Schemas/Tables

```bash
# Connect to PostgreSQL for metadata
kubectl exec -it data-platform-postgresql-0 -- psql -U postgres

# Or query Trino
trino> SHOW CATALOGS;
trino> SHOW SCHEMAS FROM postgresql;
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
- No Vault/Keycloak = no authentication/security
- No Airflow = no data ingestion/ETL
- No OpenMetadata = no governance
- Single replicas = no HA
- For production-like testing, use `values-k3s-dev.yaml`

✅ **Good for:**
- SQL query development
- Dashboard/report design
- BI exploration
- Testing Superset/Metabase configurations

## Performance Notes

- Queries on sample data: fast
- Complex queries on large datasets: may be slow (single Trino worker)
- Dashboard rendering: smooth (single Superset replica)

## Troubleshooting

### Pod won't start

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Trino connection failed

Check Trino is running:
```bash
kubectl get pods | grep trino
kubectl logs <trino-pod>
```

### Out of memory

Increase WSL2 memory:
```ini
# .wslconfig
[wsl2]
memory=8GB
```

### Can't access Trino from Superset

If using internal hostname:
- Superset → Trino: `http://data-platform-trino:8080`
- Not: `http://localhost:8080`

## See Also

- Engineer dev (DAG/dbt): `docs/engineer-dev-setup.md`
- Full-stack dev: `docs/k3s-dev-setup.md`
- Architecture: `docs/architecture.md`
