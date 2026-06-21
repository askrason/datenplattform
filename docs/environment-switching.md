# Environment Switching Guide

Quick switching between different development environments on the same k3s cluster.

## Three Environments

All three share the same **PostgreSQL** and **MinIO** data sources via persistent volumes.

### 1. Full-Stack Dev (Production-like)

```bash
./scripts/switch-to-full-stack.sh
```

**Includes:** Everything (Vault, Keycloak, Airflow, Trino, BI tools, etc.)
**RAM:** 8-16 GB
**Setup:** ~10 minutes
**Best for:** Full integration testing, security/auth testing

### 2. Engineer Dev (DAG Development)

```bash
./scripts/switch-to-engineer.sh
```

**Includes:** Airflow, Trino, PostgreSQL, MinIO
**RAM:** 4-6 GB
**Setup:** ~3-4 minutes
**Best for:** DAG/dbt development, quick iteration

### 3. Analyst Dev (BI Development)

```bash
./scripts/switch-to-analyst.sh
```

**Includes:** Trino, Superset, Metabase, PostgreSQL
**RAM:** 6-8 GB
**Setup:** ~4-5 minutes
**Best for:** Query/dashboard development

---

## Shared Data

All three environments use **the same** persistent volumes:

```
PostgreSQL (PVC):  data-platform-postgresql-data
MinIO (PVC):       data-platform-minio-data
```

**Flow:**
```
Engineer Dev
  ↓ (creates data in PostgreSQL/MinIO)
  ↓
Switch to Analyst Dev
  ↓ (sees same data)
  ↓
Switch back to Engineer Dev
  ↓ (data still there!)
```

---

## Typical Workflow

### Monday: Engineer works on DAG

```bash
./scripts/switch-to-engineer.sh

# Develop DAG
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080
# http://localhost:8080
# → Create/test DAG
# → Run DAG, data lands in MinIO/PostgreSQL
```

### Tuesday: Analyst analyzes the data

```bash
./scripts/switch-to-analyst.sh

# Same data, different tools
kubectl port-forward svc/data-platform-superset 8088:8088
# http://localhost:8088
# → Build dashboard from Engineer's data
```

### Wednesday: Engineer updates DAG

```bash
./scripts/switch-to-engineer.sh

# Same PostgreSQL/MinIO data
# → Update DAG based on Analyst feedback
# → Re-run DAG with updated logic
```

---

## Behind the Scenes

Each script does:

```bash
# 1. Check if data-platform release exists
helm list | grep data-platform

# 2. Update dependencies (if needed)
helm dependency update

# 3. Upgrade/install with role-specific values
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-ROLE-dev.yaml \
  --wait --timeout 10m

# 4. Show running pods
kubectl get pods --no-headers | grep data-platform

# 5. Print access instructions
```

**Key:** `helm upgrade` does NOT touch PVCs, so data persists.

---

## Data Persistence

### What Persists (stays)

```
✅ PostgreSQL data
✅ MinIO buckets and objects
✅ Any manual configuration in PVCs
```

### What Changes (resets)

```
❌ Pod state (gets restarted)
❌ In-memory caches
❌ Temporary files in emptyDir volumes
```

---

## Cleanup

### Remove Everything

```bash
# Remove Helm release (PVCs orphaned, not deleted)
helm uninstall data-platform

# Delete PVCs (DATA LOSS - be careful!)
kubectl delete pvc --all
```

### Keep Data, Remove Pods

```bash
# Just uninstall (PVCs remain)
helm uninstall data-platform

# Later: restore with
./scripts/switch-to-engineer.sh
# PostgreSQL/MinIO data is still there!
```

---

## Troubleshooting

### "Release not found"

First time only, script will install automatically.

### "Pod pending"

Wait a bit longer or check logs:
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### "Connection refused to PostgreSQL/MinIO"

Make sure old PVCs aren't interfering:
```bash
kubectl get pvc
kubectl get pv
```

### Out of memory

Increase WSL2:
```ini
# .wslconfig
[wsl2]
memory=16GB
```

---

## Advanced: One Release, Three Configs

Instead of switching, you could run all three as separate releases:

```bash
helm install engineer . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml

helm install analyst . \
  --values values.yaml \
  --values ci/values-analyst-dev.yaml

helm install full-stack . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml
```

**But:** Each would need separate PostgreSQL/MinIO (or shared via namespaces), so switching is cleaner.

---

## See Also

- Engineer setup: `docs/engineer-dev-setup.md`
- Analyst setup: `docs/analyst-dev-setup.md`
- Full-stack setup: `docs/k3s-dev-setup.md`
