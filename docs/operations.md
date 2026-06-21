# Data Platform Operations Guide

## Daily Checks

### PostgreSQL
```bash
kubectl exec -it <postgresql-pod> -- psql -U postgres -c "SELECT version();"
```

### Vault
```bash
kubectl exec -it <vault-pod> -- vault status
```

### MinIO
```bash
kubectl exec -it <minio-pod> -- mc stat minio/
```

### Airflow
Check https://airflow.domain/api/v1/health

---

## Secret Rotation

### PostgreSQL Password
```bash
# 1. New password in Vault
vault kv put secret/data-platform/postgresql/airflow-user \
  password="$(openssl rand -base64 32)"

# 2. Wait for ESO to sync (max 1h)
kubectl get externalSecrets

# 3. Restart dependent services
kubectl rollout restart deployment data-platform-airflow-scheduler
```

---

## Backup & Restore

### PostgreSQL
```bash
kubectl exec <postgresql-pod> -- pg_dump -U postgres > backup.sql
cat backup.sql | kubectl exec -i <postgresql-pod> -- psql -U postgres
```

---

## Disaster Recovery

### Vault Sealed
```bash
kubectl exec <vault-pod> -- vault status
# If sealed: use unseal keys to unseal
```

### Component Down
```bash
# Check pod status
kubectl get pods

# Check logs
kubectl logs <pod-name>

# Restart component
kubectl rollout restart deployment <component>
```

---

## Upgrade Checklist

1. Backup PostgreSQL
2. helm dependency update
3. helm upgrade with --dry-run
4. helm upgrade (actual)
5. helm test data-platform
6. Verify all pods running

---

## Monitoring

- PostgreSQL: Check replication lag
- Vault: Check if unsealed
- MinIO: Check available capacity
- Airflow: Monitor DAG run success rate
