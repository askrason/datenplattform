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

## WICHTIGER FUND (diese Überarbeitung) – Secret-Bootstrap erforderlich

`vault.enabled: false` und `external-secrets.enabled: false` bedeuten: Es gibt
**keinen** Mechanismus mehr, der die von PostgreSQL/Airflow/Trino/MinIO über
`existingSecret`-Felder referenzierten Kubernetes-Secrets erzeugt (das macht
normalerweise ausschließlich ESO via ClusterSecretStore, siehe TICKET-004).
Ohne Vault bleiben diese Secrets schlicht nicht vorhanden, und betroffene Pods
hängen in `CreateContainerConfigError`.

**Lösung:** Ein zusätzliches Bootstrap-Script legt für dieses Dev-Profil die
benötigten Secrets direkt als Klartext-`kubectl create secret`-Objekte an –
*ausschließlich* für den lokalen, ephemeren k3s-Cluster. Das ist eine bewusste,
eng begrenzte Ausnahme von der "Kein Klartext"-Regel aus CLAUDE.md (die sich
auf `values.yaml`/Templates im Repo bezieht, nicht auf zur Laufzeit generierte,
nie committete Dev-Secrets). Siehe auch CLAUDE.md, Known Issue #7.

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-013
Neue Dateien: ci/values-engineer-dev.yaml, scripts/setup-engineer-dev.sh,
  scripts/bootstrap-dev-secrets.sh, docs/engineer-dev-setup.md
Überarbeitung: Auth-Fallback (AUTH_DB) + Secret-Bootstrap-Anforderung
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

# Airflow: Full Stack (DAG Development Focus)
# OHNE Keycloak -> AUTH_DB statt OIDC (keine Keycloak-OIDC im Dev)
airflow:
  scheduler:
    resources:
      requests: { cpu: 250m, memory: 512Mi }
      limits: { cpu: 500m, memory: 1Gi }
  webserverConfig: |
    # Dev-Profil ohne Keycloak: einfache Passwort-Auth statt OIDC.
    from airflow.www.security import AirflowSecurityManager
    AUTH_TYPE = 1  # AUTH_DB – Standard-Login mit lokal angelegtem Admin-User
    AUTH_USER_REGISTRATION = False

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
