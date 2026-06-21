# TICKET-015: Data Analyst Dev-Environment (WSL2 / k3s)

## Ziel
Data Analysts können lokal auf WSL2 + k3s eine **Trino + Superset/Metabase + PostgreSQL** Umgebung deployen.
Fokus: Query-Entwicklung, Dashboard/Report-Design, BI-Exploration.
**OHNE** Vault, Keycloak, Airflow, OpenMetadata (nicht relevant für BI-Dev).
Ressourcen: 6-8 GB RAM. Start-Zeit: ~4-5 Minuten.

## Voraussetzungen
- TICKET-001 bis TICKET-013 abgeschlossen
- WSL2 mit ca. 6-8 GB RAM
- kubectl und helm installiert

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-013
Neue Dateien: ci/values-analyst-dev.yaml, scripts/setup-analyst-dev.sh, docs/analyst-dev-setup.md
```

## Zu erstellende Dateien

### 1. `ci/values-analyst-dev.yaml`

Override-Datei für Data Analyst Dev-Umgebung. Fokus auf: Trino, Superset/Metabase, PostgreSQL.

```yaml
# Data Analyst Dev: Trino + Superset/Metabase + PostgreSQL (minimal)
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

# Trino: Minimal (Query Engine - this is the focus)
trino:
  server:
    workers: 1
  coordinator:
    resources:
      requests: { cpu: 500m, memory: 1Gi }
      limits: { cpu: 1000m, memory: 2Gi }

# Superset: Single Replica (Primary BI Tool)
superset:
  replicaCount: 1
  celeryWorker:
    replicaCount: 1
  redis:
    master:
      resources:
        requests: { cpu: 50m, memory: 128Mi }
        limits: { cpu: 100m, memory: 256Mi }

# Metabase: Single Replica (Secondary BI Tool)
metabase:
  replicaCount: 1

# MinIO: Optional (can use external S3)
minio:
  enabled: false

# DISABLED: Orchestration not needed for BI development
airflow:
  enabled: false

# DISABLED: Security/Governance not needed for Query/Dashboard development
vault:
  enabled: false

external-secrets:
  enabled: false

keycloak:
  enabled: false

openmetadata:
  enabled: false
```

### 2. `scripts/setup-analyst-dev.sh`

Setup-Script für Analyst Dev-Umgebung.

```bash
#!/bin/bash
set -euo pipefail

echo "=== Data Analyst Dev-Environment Setup ==="
echo "Trino + Superset + Metabase + PostgreSQL (NO Vault/Keycloak/Airflow)"
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

# Deploy Data Platform (Analyst Edition)
echo "→ Deploying Trino + Superset + Metabase + PostgreSQL..."
echo "   (this may take 4-5 minutes)"
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-analyst-dev.yaml \
  --wait --timeout 10m

echo ""
echo "✓ Data Analyst Dev-Environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Check pod status:"
echo "     kubectl get pods"
echo ""
echo "  2. Access Trino:"
echo "     kubectl port-forward svc/data-platform-trino 8080:8080"
echo "     Then: http://localhost:8080/ui/"
echo ""
echo "  3. Access Superset:"
echo "     kubectl port-forward svc/data-platform-superset 8088:8088"
echo "     Then: http://localhost:8088"
echo ""
echo "  4. Access Metabase:"
echo "     kubectl port-forward svc/data-platform-metabase 3000:3000"
echo "     Then: http://localhost:3000"
echo ""
echo "For more info, see docs/analyst-dev-setup.md"
EOF
