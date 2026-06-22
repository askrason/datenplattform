# Quick Start Guide

Deploy the Data Platform in 10 minutes. For detailed setup, see `docs/installation.md`.

---

## Prerequisites (5 min)

```bash
# Check tools are installed
helm version      # 3.19+
kubectl version   # 1.32+
git --version

# Prepare cluster
kubectl create namespace data-platform

# Add Helm repos
helm repo add vault https://helm.releases.hashicorp.com
helm repo add apache https://airflow.apache.org
helm repo add trinodb https://trinodb.github.io/charts
helm repo update
```

---

## Clone & Deploy (5 min)

```bash
# 1. Clone repo
git clone https://github.com/askrason/datenplattform.git
cd datenplattform

# 2. Update domain (CRITICAL!)
vim values.yaml
# Change: global.domain = "your-domain.com"

# 3. Get dependencies
helm dependency update

# 4. Validate
./scripts/validate.sh

# 5. Install
helm install data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --wait --timeout 20m

# 6. Check status
kubectl get pods -n data-platform
```

---

## Access Services (After DNS/TLS ready)

```bash
# Services are available at:
# - https://airflow.your-domain.com         (Admin: admin/airflow)
# - https://superset.your-domain.com        (Admin: admin/admin)
# - https://metabase.your-domain.com        (OAuth via Keycloak)
# - https://openmetadata.your-domain.com    (Admin: admin/admin)
# - https://keycloak.your-domain.com/admin  (Admin: admin/changeme)

# Or port-forward for quick access:
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080 -n data-platform &
# http://localhost:8080
```

---

## Essential Post-Deploy

```bash
# 1. Unseal Vault (if using Shamir)
kubectl port-forward svc/data-platform-vault 8200:8200 -n data-platform &
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# 2. Change Keycloak admin password
kubectl port-forward svc/data-platform-keycloak 8080:80 -n data-platform &
# http://localhost:8080/admin → admin / changeme → Change password!

# 3. Verify all services healthy
kubectl get pods -n data-platform
# All should be Running/Ready
```

---

## Troubleshooting

```bash
# Check pod status
kubectl describe pod <pod-name> -n data-platform

# View logs
kubectl logs <pod-name> -n data-platform

# Check if ExternalSecrets are synced
kubectl get externalsecret -n data-platform

# Port-forward for debugging
kubectl port-forward svc/data-platform-postgresql 5432:5432 -n data-platform
kubectl port-forward svc/data-platform-vault 8200:8200 -n data-platform
```

---

## Next Steps

- Read `docs/installation.md` for production setup
- Check `docs/operations.md` for daily operations
- See `CLAUDE.md` for architecture & ADRs
- Run `./scripts/validate.sh` before any commit

---

**Questions? See:**
- Full installation guide: `docs/installation.md`
- Troubleshooting: `docs/operations.md`
- Architecture: `docs/architecture.md`
