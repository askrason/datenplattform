# Installations- & Deployment-Anleitung

Production-ready Deployment der Data Platform Helm Chart auf Kubernetes.

---

## Übersicht

Diese Anleitung behandelt das Deployment der kompletten Data Platform auf einem Kubernetes-Cluster (1.32+).

**Version**: v1.1+ mit **Multi-Namespace-Architektur** (7 isolierte Namespaces statt Single-Namespace)
- Siehe `docs/MULTI-NAMESPACE-REFACTOR-SUMMARY.md` für Details
- Service Discovery über FQDN (z.B. `postgresql.data-storage.svc.cluster.local`)
- Deny-by-default NetworkPolicies pro Namespace

Für lokale Entwicklung siehe:
- **k3s Dev**: `docs/k3s-dev-setup.md` (automated cluster setup)
- **Engineer Dev**: `docs/engineer-dev-setup.md`
- **Analyst Dev**: `docs/analyst-dev-setup.md`

---

## Voraussetzungen

### Kubernetes-Cluster
- Kubernetes 1.32+
- kubeconfig konfiguriert und funktionsfähig
- Ausreichend Ressourcen (mindestens 16 GB RAM, 8 CPUs für Single-Node; mehr für HA)

### Infrastruktur
- **Ingress Controller** (z.B. ingress-nginx) mit TLS-Terminierung
- **cert-manager** für automatische TLS-Zertifikat-Verwaltung
- **StorageClass** mit ReadWriteOnce-Support (z.B. `standard`, `gp3`)

### Tools
```bash
# Erforderlich
helm 3.19+
kubectl 1.32+
git

# Optional (empfohlen)
trivy              # für Security-Scans
helm-unittest      # für Test-Validierung
```

### DNS & Netzwerk
- Domain-Name, der auf deinen Cluster zeigt (z.B. `data-platform.example.com`)
- Wildcard-DNS oder einzelne A-Records für jeden Service
- Network Policies aktiviert (oder können später aktiviert werden)

---

## Schritt 1: Repository klonen & vorbereiten

```bash
git clone https://github.com/askrason/datenplattform.git
cd datenplattform

# Struktur überprüfen
ls -la
# → Chart.yaml, values.yaml, CLAUDE.md, docs/, scripts/, templates/, etc.
```

---

## Schritt 2: Konfiguration prüfen

### CLAUDE.md lesen
```bash
# Unbedingt lesen – enthält:
# - ADRs (Architecture Decision Records)
# - Security Baseline (NON-NEGOTIABLE)
# - Known Issues (besonders #6 Bitnami OCI Migration)
cat CLAUDE.md | head -100
```

### Known Issues prüfen
Besonders wichtig:
- **Known Issue #6**: Bitnami OCI Migration (PostgreSQL, Keycloak Image-Tags)
- **Known Issue #7**: Multi-Namespace Architektur (v1.1+) – Service Discovery via FQDN required
- **Known Issue #8**: Dev-Profile Secrets (nur für lokale Cluster)

### values.yaml anpassen

```bash
vim values.yaml
```

Diese kritischen Werte aktualisieren:

```yaml
global:
  domain: "data-platform.example.com"    # Deine Domain
  storageClass: "standard"                # Oder die Klasse deines Cloud-Providers
  imageRegistry: "docker.io"              # Kann private Registry sein
  imagePullPolicy: IfNotPresent           # Gut für Air-Gapped
  # imagePullSecrets:                     # Falls private Registry
  #   - name: regcred

vault:
  enabled: true                           # Immer true für Production

keycloak:
  enabled: true                           # Immer true für Production

# Andere: Defaults behalten oder nach Bedarf anpassen
```

---

## Schritt 3: Kubernetes-Cluster vorbereiten

### Namespace erstellen
```bash
kubectl create namespace data-platform
# Oder --namespace in helm install nutzen
```

### Ingress Controller installieren (falls nicht vorhanden)
```bash
# Beispiel: ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --values - << 'EOF'
controller:
  service:
    type: LoadBalancer  # oder NodePort für On-Prem
  metrics:
    enabled: true
EOF
```

### cert-manager installieren (falls nicht vorhanden)
```bash
# cert-manager für automatische TLS
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
```

### External Secrets Operator installieren (falls nicht vorhanden)
```bash
# ESO wird als Helm-Dependency installiert, kann aber auch vorher installiert werden
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

---

## Schritt 4: Helm Dependencies vorbereiten

```bash
# Helm Repository Indizes aktualisieren
helm repo add vault https://helm.releases.hashicorp.com
helm repo add apache https://airflow.apache.org
helm repo add trinodb https://trinodb.github.io/charts
helm repo add open-metadata https://helm.open-metadata.org
helm repo add apache-superset https://apache.github.io/superset
helm repo update

# Chart-Dependencies herunterladen
helm dependency update

# Dependencies überprüfen
ls -la charts/
```

---

## Schritt 5: Pre-Deployment Validierung

```bash
# Chart-Syntax validieren
./scripts/validate.sh

# Template-Rendering (Dry-Run)
helm template data-platform . \
  --values values.yaml \
  --output-dir /tmp/rendered

# Offensichtliche Probleme prüfen
kubectl apply --dry-run=client -f /tmp/rendered/data-platform/templates/ 2>&1 | head -20
```

---

## Schritt 6: Vault initialisieren (KRITISCH!)

**VOR dem Deployment der Chart** muss Vault initialisiert und entsperrt werden.

### Option A: Vault Auto Unseal (Cloud KMS)
Empfohlen für Production. In `values/vault.yaml` konfigurieren:

```yaml
vault:
  server:
    ha:
      enabled: true
    config: |
      seal "awskms" {
        region = "us-east-1"
        kms_key_id = "arn:aws:kms:..."
      }
      # ... rest der Konfiguration
```

### Option B: Manuelles Entsperren (Shamir)
```bash
# Nach Chart-Deployment (siehe Schritt 7) manuell entsperren:
kubectl port-forward svc/data-platform-vault 8200:8200 &

# In anderem Terminal:
vault operator init -key-shares=5 -key-threshold=3
# Unseal-Keys und Root-Token SICHER speichern

vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>

# Status prüfen:
vault status
```

Unseal-Keys und Root-Token in einem **sicheren Vault** speichern (z.B. verschlüsselter Password Manager, Bitwarden, 1Password).

---

## Schritt 7: Chart deployen

### Standard Deployment (Production)

```bash
helm install data-platform . \
  --namespace data-platform \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 20m
```

### Mit Custom Domain

```bash
helm install data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --set global.domain="deine-domain.com" \
  --wait \
  --timeout 20m
```

### Mit Private Image Registry

```bash
# Erst Image-Pull-Secret erstellen
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=benutzer \
  --docker-password=passwort \
  --namespace data-platform

# Dann mit folgender Installation:
helm install data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --set global.imagePullSecrets[0].name=regcred \
  --wait
```

---

## Schritt 8: Deployment überprüfen

```bash
# Alle Pods sollten laufen
kubectl get pods -n data-platform

# Services prüfen
kubectl get svc -n data-platform

# Ingress prüfen
kubectl get ingress -n data-platform

# Ingress sollte externe IP haben
kubectl get ingress -n data-platform -o wide
```

Erwartete Ausgabe:
```
NAME                                    READY   STATUS    RESTARTS
data-platform-vault-0                   1/1     Running   0
data-platform-postgresql-0              1/1     Running   0
data-platform-minio-0                   1/1     Running   0
data-platform-airflow-scheduler-xxx     1/1     Running   0
data-platform-airflow-webserver-xxx     1/1     Running   0
...
```

---

## Schritt 9: Keycloak initialisieren

```bash
# Port-Forward zu Keycloak
kubectl port-forward svc/data-platform-keycloak 8080:80 -n data-platform &

# Admin-Konsole aufrufen:
# http://localhost:8080/admin

# Standard-Anmeldedaten (aus values/keycloak.yaml):
# Benutzer: admin
# Passwort: changeme (SOFORT in values.yaml ändern!)

# Realm importieren
# - Gehe zu Administration → Realms → Import
# - Lade auf: files/keycloak-realm.json
# - Klicke Import
```

Oder über CLI:
```bash
# Aktuellen Realm exportieren
kubectl exec data-platform-keycloak-0 -n data-platform -- \
  /opt/keycloak/bin/kc.sh export \
  --realm master \
  --dir /tmp

# Realm importieren
kubectl exec data-platform-keycloak-0 -n data-platform -- \
  /opt/keycloak/bin/kc.sh import \
  --realm-dir /tmp
```

---

## Schritt 10: PostgreSQL initialisieren

```bash
# PostgreSQL-Erreichbarkeit prüfen
kubectl exec -it data-platform-postgresql-0 -n data-platform -- \
  psql -U postgres -c "\l"

# Erwartete Datenbanken: postgres, airflow, metabase, superset, openmetadata

# Falls Datenbanken fehlen, erstellen:
kubectl exec -it data-platform-postgresql-0 -n data-platform -- psql -U postgres << 'EOF'
CREATE DATABASE airflow;
CREATE DATABASE metabase;
CREATE DATABASE superset;
CREATE DATABASE openmetadata;
EOF
```

---

## Schritt 11: DNS & TLS konfigurieren

### DNS-Records hinzufügen

```bash
# Externe IP des Ingress abrufen
kubectl get ingress -n data-platform -o wide

# A-Records erstellen (oder CNAME)
# In deinem DNS-Provider:
# data-platform.example.com       → <EXTERNAL-IP>
# airflow.example.com             → <EXTERNAL-IP>
# superset.example.com            → <EXTERNAL-IP>
# metabase.example.com            → <EXTERNAL-IP>
# openmetadata.example.com        → <EXTERNAL-IP>
# vault.example.com               → <EXTERNAL-IP> (oder nur intern)
# keycloak.example.com            → <EXTERNAL-IP>
```

### TLS-Zertifikate überprüfen

```bash
# cert-manager sollte automatisch Zertifikate erstellen
kubectl get certificate -n data-platform

# Zertifikat-Status prüfen
kubectl describe certificate data-platform-tls -n data-platform

# Erwartet: Certificate is valid for *.example.com
```

---

## Schritt 12: Platform aufrufen

Sobald DNS + TLS bereit sind:

| Service | URL | Standard-Anmeldedaten |
|---------|-----|----------------------|
| Airflow | https://airflow.example.com | admin / airflow |
| Superset | https://superset.example.com | admin / admin |
| Metabase | https://metabase.example.com | admin@example.com / (via OAuth) |
| OpenMetadata | https://openmetadata.example.com | admin / admin |
| Keycloak | https://keycloak.example.com/admin | admin / changeme |
| Vault | https://vault.example.com | Root-Token |
| MinIO Console | https://minio.example.com | minioadmin / minioadmin |

**Standard-Passwörter sofort ändern!**

---

## Fehlerbehebung

### Pods stuck in CreateContainerConfigError

```bash
# Secrets überprüfen
kubectl get secret -n data-platform

# Pod-Events prüfen
kubectl describe pod <pod-name> -n data-platform

# Wahrscheinlich fehlendes Secret – ExternalSecrets überprüfen
kubectl get externalsecret -n data-platform
kubectl describe externalsecret <name> -n data-platform

# Vault-Verbindung überprüfen
kubectl logs -n data-platform -l app.kubernetes.io/name=external-secrets
```

### Ingress funktioniert nicht

```bash
# Ingress-Status prüfen
kubectl describe ingress data-platform-airflow -n data-platform

# DNS prüfen
nslookup airflow.example.com

# Von Pod testen
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n data-platform -- \
  curl -v https://airflow.example.com/health
```

### Vault-Probleme

```bash
# Vault-Status prüfen
kubectl exec data-platform-vault-0 -n data-platform -- vault status

# Vault-Logs prüfen
kubectl logs data-platform-vault-0 -n data-platform

# Falls Entsperren nötig
kubectl port-forward svc/data-platform-vault 8200:8200 -n data-platform
vault operator unseal <key>
```

---

## Post-Deployment-Aufgaben

1. **Standard-Passwörter ändern**
   - Keycloak Admin
   - PostgreSQL Benutzer
   - MinIO Anmeldedaten

2. **SMTP konfigurieren** (für Benachrichtigungen)
   - Airflow
   - Superset
   - OpenMetadata

3. **Backups einrichten**
   - PostgreSQL
   - MinIO Buckets
   - Vault Daten

4. **Monitoring aktivieren**
   - Prometheus (optional)
   - Grafana (optional)
   - Log-Aggregation

5. **Container-Images laden** (falls Air-Gapped)
   - Siehe `docs/image-management.md`
   - Führe `./scripts/load-container-images.sh` aus

6. **Validierung starten**
   ```bash
   ./scripts/validate.sh
   ```

---

## Updates

```bash
# Chart-Version in Chart.yaml aktualisieren
vim Chart.yaml

# Dependencies aktualisieren
helm dependency update

# Dry-Run des Updates
helm upgrade data-platform . \
  --dry-run \
  --debug \
  --namespace data-platform \
  --values values.yaml

# Tatsächliches Update
helm upgrade data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --wait
```

---

## Deinstallation

**WARNUNG:** Dies löscht alle Deployments, behält aber PVCs.

```bash
# Chart löschen
helm uninstall data-platform -n data-platform

# Namespace und PVCs für späteren Restore behalten
# Oder alles löschen:
kubectl delete namespace data-platform  # ⚠️ DATENVERLUST
```

---

## Siehe auch

- **Sicherheit**: CLAUDE.md, `docs/security-scanning.md`
- **Fehlerbehebung**: `docs/operations.md`
- **Architektur**: `docs/architecture.md`
- **Dev Deployment**: `docs/k3s-dev-setup.md`
- **Air-Gapped**: `docs/offline-deployment.md`
