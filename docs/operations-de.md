# Data Platform Operations Guide

## Tägliche Checks

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

## Secret-Rotation

### PostgreSQL-Passwort
```bash
# 1. Neues Passwort in Vault
vault kv put secret/data-platform/postgresql/airflow-user \
  password="$(openssl rand -base64 32)"

# 2. Warte auf ESO-Sync (max 1h)
kubectl get externalSecrets

# 3. Starte abhängige Services neu
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

### Vault Versiegelt
```bash
kubectl exec <vault-pod> -- vault status
# Falls versiegelt: Nutze Unseal-Keys zum Entsperren
```

### Komponente Down
```bash
# Überprüfe Pod-Status
kubectl get pods

# Überprüfe Logs
kubectl logs <pod-name>

# Starte Komponente neu
kubectl rollout restart deployment <component>
```

---

## Upgrade-Checkliste

1. Backup PostgreSQL
2. helm dependency update
3. helm upgrade with --dry-run
4. helm upgrade (aktuell)
5. helm test data-platform
6. Verifiziere alle Pods laufen

---

## Monitoring

- PostgreSQL: Überprüfe Replikation-Lag
- Vault: Überprüfe, ob entsperrt
- MinIO: Überprüfe verfügbare Kapazität
- Airflow: Monitore DAG Run Success Rate
