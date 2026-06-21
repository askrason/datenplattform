# TICKET-014: Data Engineer Dev-Environment (WSL2 / k3s)

## Ziel
Data Engineers können lokal auf WSL2 + k3s eine **Airflow + Trino + PostgreSQL + MinIO** Umgebung deployen.
Fokus: DAG-Entwicklung, dbt-Transformationen, SQL-Queries.
**OHNE** Vault, Keycloak, OpenMetadata (Security nicht relevant für DAG-Dev).
Ressourcen: 4-6 GB RAM. Start-Zeit: ~3-4 Minuten.

## Voraussetzungen
- TICKET-001 bis TICKET-013 abgeschlossen
- WSL2 mit ca. 4-6 GB RAM
- kubectl und helm installiert

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-013
Neue Dateien: ci/values-engineer-dev.yaml, scripts/setup-engineer-dev.sh, docs/engineer-dev-setup.md
```

## Zu erstellende Dateien

### 1. `ci/values-engineer-dev.yaml`

Override-Datei für Data Engineer Dev-Umgebung. Fokus auf: Airflow, Trino, PostgreSQL, MinIO.

```yaml
# Data Engineer Dev: Airflow + Trino + PostgreSQL + MinIO (minimal)
# NO Security (Vault, Keycloak disabled)

# Storage: k3s local-path
global:
  storageClass: "local-path"

# PostgreSQL: Single Primary
postgresql:
  primary:
    replicaCount: 1
  readReplicas:
    enabled: false
  persistence:
    size: 20Gi

# Airflow: Full Stack (this is the focus)
airflow:
  scheduler:
    resources:
      requests: { cpu: 250m, memory: 512Mi }
      limits: { cpu: 500m, memory: 1Gi }

# Trino: Minimal
trino:
  server:
    workers: 1
  coordinator:
    resources:
      requests: { cpu: 250m, memory: 500Mi }
      limits: { cpu: 500m, memory: 1Gi }

# MinIO: Standalone
minio:
  mode: standalone
  replicas: 1
  persistence:
    size: 50Gi

# DISABLED: Security/Governance not needed for DAG development
vault:
  enabled: false

external-secrets:
  enabled: false

keycloak:
  enabled: false

openmetadata:
  enabled: false

# DISABLED: BI Tools (not needed for DAG development)
superset:
  enabled: false

metabase:
  enabled: false
```

### 2. `scripts/setup-engineer-dev.sh`

Setup-Script für Engineer Dev-Umgebung.

```bash
#!/bin/bash
set -euo pipefail

echo "=== Data Engineer Dev-Environment Setup ==="
echo "Airflow + Trino + PostgreSQL + MinIO (NO Vault/Keycloak)"
echo ""

# Check prerequisites
echo "→ Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found. Please install kubectl."
  exit 1
fi

if ! command -v helm &> /dev/null; then
  echo "❌ helm not found. Please install helm."
  exit 1
fi

echo "✓ kubectl and helm found"
echo ""

# Update Helm dependencies
echo "→ Updating Helm dependencies..."
helm dependency update >/dev/null 2>&1
echo "✓ Dependencies updated"

# Deploy Data Platform (Engineer Edition)
echo "→ Deploying Airflow + Trino + PostgreSQL + MinIO..."
echo "   (this may take 3-4 minutes)"
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --wait --timeout 10m

echo ""
echo "✓ Data Engineer Dev-Environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Check pod status:"
echo "     kubectl get pods"
echo ""
echo "  2. Access Airflow:"
echo "     kubectl port-forward svc/data-platform-airflow-webserver 8080:8080"
echo "     Then: http://localhost:8080"
echo ""
echo "  3. Access Trino:"
echo "     kubectl port-forward svc/data-platform-trino 8080:8080"
echo "     Then: http://localhost:8080/ui/"
echo ""
echo "  4. Create DAG:"
echo "     kubectl exec -it <airflow-scheduler-pod> -- bash"
echo "     # Place DAGs in /opt/airflow/dags/"
echo ""
echo "For more info, see docs/engineer-dev-setup.md"
EOF
