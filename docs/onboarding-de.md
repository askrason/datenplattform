# Onboarding für neue Entwickler

## Voraussetzungen (Lokal)

```bash
# Erforderliche Tools
kubectl version --client
helm version
kind --version
git --version

# Optional
docker --version
vault version (für lokales Vault-Testen)
```

## Setup-Schritte

### 1. Repository klonen
```bash
git clone https://github.com/askrason/datenplattform.git
cd datenplattform
```

### 2. Lese CLAUDE.md
```bash
cat CLAUDE.md
# Fokus auf:
# - Security Baseline (NON-NEGOTIABLE)
# - Coding Conventions
# - ADRs (Architecture Decision Records)
```

### 3. Starte Kind Cluster
```bash
kind create cluster --config ci/kind-config.yaml
kind get clusters
```

### 4. Installiere Abhängigkeiten
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add apache https://airflow.apache.org
helm repo add trinodb https://trinodb.github.io/charts
helm repo update
helm dependency update
```

### 5. Deploye Chart (Lokaler Test)
```bash
helm install data-platform . \
  --values values.yaml \
  --wait --timeout 10m
```

### 6. Verifiziere Deployment
```bash
kubectl get pods
kubectl get svc
helm test data-platform --timeout 5m
```

## Wichtige Konventionen

1. **Lese CLAUDE.md** vor beliebigen Änderungen
2. **Keine Klartext-Secrets** in values.yaml → nutze Vault + ExternalSecret
3. **Security-Exceptions immer kommentiert** (readOnlyRootFilesystem: false)
4. **Teste NetworkPolicies** vor PR
5. **Resource Limits erforderlich** für jeden Container

## Häufige Fehler

| Fehler | Lösung |
|--------|--------|
| "Klartext-Passwort in values.yaml" | Move zu Vault, referenziere via ExternalSecret |
| "Pod startet nicht" | Überprüfe readOnlyRootFilesystem + emptyDir Volumes |
| "ESO Secret blockiert" | Ist Vault entsperrt? Besitzt Pod RBAC für Secrets? |
| "OIDC Login schlägt fehl" | Keycloak Client-Secret in Vault? Redirect-URI korrekt? |
| "NetworkPolicy zu streng" | Füge Ingress/Egress Regeln hinzu, teste mit curl von Test-Pod |

## Typischer Workflow

1. Feature Branch erstellen: `git checkout -b feature/TICKET-XXX`
2. Ändere Values in values/*.yaml oder templates/
3. Führe Validierung aus: `./scripts/validate.sh`
4. Teste lokal: `helm upgrade data-platform . --dry-run`
5. Commit: `git commit -am "feat: TICKET-XXX - Description"`
6. Push: `git push origin feature/TICKET-XXX`
7. Erstelle PR auf GitHub
8. CI läuft Lint + Tests
9. Merge nach Review

## Dokumentations-Dateien (ZUERST LESEN)

- `CLAUDE.md` - Projekt-Konventionen & ADRs
- `docs/architecture.md` - System-Design
- `docs/networking.md` - Netzwerk-Richtlinien & Konnektivität
- `docs/operations.md` - Runbook für Operatoren
- `docs/keycloak-setup.md` - Keycloak Deployment-Schritte
- `docs/metabase-setup.md` - Metabase Post-Deploy-Konfiguration

## Hilfe bekommen

- Überprüfe bestehende docs/ Dateien
- Lese CLAUDE.md ADR-Sektionen
- Suche GitHub Issues
- Frage in Team Slack Channel
