# TICKET-011: Integration Tests + helm test Suite

## Ziel
Eine vollständige `helm test`-Suite erstellen, die nach dem Deployment die
Konnektivität und Grundfunktionalität aller Stack-Komponenten verifiziert.
Zusätzlich: lokale Validierungs-Skripte und CI-Konfiguration.

## Voraussetzungen
- TICKET-001 bis TICKET-010 abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-010
Neue Dateien: templates/tests/*.yaml, ci/kind-config.yaml,
  ci/test-pipeline.yaml (GitLab CI), scripts/validate.sh (erweitert)
```

## Zu erstellende Dateien

### 1. `templates/tests/test-postgresql-connection.yaml`
(Bereits in TICKET-002 vorbereitet – hier finalisieren)

```yaml
# Prüft: Primary erreichbar, alle 6 DBs vorhanden, alle User authentifizieren sich
# Image: postgres:16-alpine (readOnlyRootFilesystem: true möglich)
# annotations: "helm.sh/hook": test, "helm.sh/hook-delete-policy": before-hook-creation
```

### 2. `templates/tests/test-minio-connection.yaml`
(Bereits in TICKET-003 vorbereitet – hier finalisieren)

```yaml
# Prüft: API Port 9000 erreichbar, alle 7 Buckets existieren,
# Service-User airflow-svc und trino-svc können sich authentifizieren
# Image: minio/mc:latest
```

### 3. `templates/tests/test-airflow-health.yaml`
(Bereits in TICKET-005 vorbereitet – hier finalisieren)

```yaml
# Prüft: /health Endpoint → {"status": "healthy"}
#        Scheduler-Status in der API
#        DAG-Liste abrufbar
# Image: curlimages/curl:8.x
# Kein Auth (intern, NetworkPolicy schützt)
```

### 4. `templates/tests/test-trino-connectivity.yaml`

```yaml
# Prüft:
# - Trino UI Port 8080 erreichbar (HTTP 200)
# - SHOW CATALOGS enthält: minio, iceberg, postgresql
# - SELECT 1 erfolgreich (Basis-Query)
# Image: trinodb/trino:latest (enthält trino CLI)
# Command: trino --server http://{{ trino-host }}:8080 --execute "SHOW CATALOGS"
```

### 5. `templates/tests/test-openmetadata-health.yaml`

```yaml
# Prüft:
# - /api/v1/system/status → {"status": "up"}
# - Datenbankverbindung (via Status-Endpoint)
# Image: curlimages/curl:8.x
```

### 6. `templates/tests/test-superset-health.yaml`

```yaml
# Prüft:
# - /health Endpoint → "OK"
# - Login-Seite erreichbar (302 Redirect zu Keycloak = Erfolg)
# Image: curlimages/curl:8.x
```

### 7. `templates/tests/test-vault-health.yaml`

```yaml
# Prüft:
# - Vault ist initialized: true
# - Vault ist sealed: false (alle 3 Replicas)
# - ESO ClusterSecretStore Status: Ready
# Image: hashicorp/vault:latest
# Command: vault status -address=http://{{ vault-host }}:8200
```

### 8. `templates/tests/test-keycloak-health.yaml`

```yaml
# Prüft:
# - /health/ready → {"status": "UP"}
# - Realm data-platform existiert (GET /realms/data-platform)
# - Alle 6 OIDC-Clients vorhanden
# Image: curlimages/curl:8.x
```

### 9. `templates/tests/test-network-isolation.yaml`

```yaml
# Prüft Deny-by-default NetworkPolicy:
# - Ein Test-Pod im Namespace kann NICHT direkt auf PostgreSQL (5432) zugreifen
#   wenn er kein entsprechendes Label hat
# - Ein Test-Pod kann NICHT auf MinIO (9000) zugreifen ohne Label
# Erwartet: Connection Timeout (kein Refuse, da Drop-Policy)
# Image: curlimages/curl:8.x mit --connect-timeout 5
# annotations: "helm.sh/hook": test
```

### 10. `ci/kind-config.yaml`

Lokales Kind-Cluster für Entwicklung:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
```

### 11. `ci/test-pipeline.yaml` (GitLab CI)

```yaml
stages:
  - validate
  - lint
  - test

variables:
  HELM_VERSION: "3.19.0"

lint:
  stage: lint
  image: alpine/helm:${HELM_VERSION}
  script:
    - helm dependency update
    - helm lint . --values values.yaml --strict
    - helm template data-platform . --values values.yaml > /dev/null

validate-schema:
  stage: validate
  script:
    - helm lint . --values values.yaml
    - helm template . --values values.yaml | kubectl apply --dry-run=client -f -

integration-test:
  stage: test
  when: manual   # nur auf expliziten Trigger
  script:
    - kind create cluster --config ci/kind-config.yaml
    - helm dependency update
    - helm install data-platform . --values values.yaml --wait --timeout 10m
    - helm test data-platform --timeout 5m --logs
```

### 12. `scripts/validate.sh` (erweitert)

```bash
#!/bin/bash
set -euo pipefail

echo "=== Data Platform Helm Chart Validation ==="

echo "→ Dependency Update..."
helm dependency update 2>&1

echo "→ Lint (strict)..."
helm lint . --values values.yaml --strict

echo "→ Template Rendering..."
helm template data-platform . --values values.yaml > /tmp/rendered.yaml
echo "  Rendered $(wc -l < /tmp/rendered.yaml) Zeilen YAML"

echo "→ Kubernetes Dry-Run..."
kubectl apply --dry-run=client -f /tmp/rendered.yaml

echo "→ Security-Check: Keine Klartext-Secrets..."
if grep -r "password:" values/ values.yaml | grep -v "existingSecret\|#\|''\|\"\""; then
  echo "❌ FEHLER: Klartext-Passwort gefunden!"
  exit 1
fi

echo "→ Security-Check: runAsNonRoot überall gesetzt..."
ROOT_CONTAINERS=$(grep -r "runAsNonRoot: false" templates/ || true)
if [ -n "$ROOT_CONTAINERS" ]; then
  echo "❌ FEHLER: runAsNonRoot: false gefunden:"
  echo "$ROOT_CONTAINERS"
  exit 1
fi

echo "→ Security-Check: Alle Container haben Resource Limits..."
# Prüft ob 'limits:' in jedem Komponenten-values-File vorkommt
for f in values/*.yaml; do
  if ! grep -q "limits:" "$f"; then
    echo "⚠️  WARNUNG: Keine Resource Limits in $f"
  fi
done

echo ""
echo "✓ Alle Validierungen erfolgreich"
```

## Akzeptanzkriterien

- [ ] `helm test data-platform` läuft durch (alle 8 Test-Pods: Passed)
- [ ] `test-network-isolation` schlägt fehl wenn NetworkPolicy NICHT aktiv ist (negativer Test)
- [ ] `scripts/validate.sh` erkennt Klartext-Passwörter und schlägt fehl
- [ ] `scripts/validate.sh` erkennt `runAsNonRoot: false` und schlägt fehl
- [ ] CI-Pipeline Lint-Stage läuft in < 2 Minuten
- [ ] Kind-Cluster-Config für lokale Tests vorhanden
- [ ] Alle Test-Pods: `readOnlyRootFilesystem: true`, `runAsNonRoot: true`
- [ ] Test-Pods werden nach Ausführung gelöscht (`hook-delete-policy: before-hook-creation`)
