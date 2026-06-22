# k3s Entwicklungsumgebungs-Setup (WSL2)

## Voraussetzungen

- **WSL2** mit 8-16 GB RAM
- **kubectl** und **helm** lokal installiert
- **Git** Repository geklont

## Schnellstart

```bash
cd datenplattform
chmod +x scripts/setup-k3s-dev.sh
./scripts/setup-k3s-dev.sh
```

Das ist alles! Die Umgebung ist in 5-10 Minuten bereit.

---

## Funktionsweise

Das Setup-Skript führt Folgendes durch:

1. **Überprüfung der Voraussetzungen** (kubectl, helm)
2. **Installation von cert-manager** (für TLS-Zertifikatverwaltung)
3. **Installation von ingress-nginx** (für Ingress-Routing)
4. **Aktualisierung der Helm-Abhängigkeiten** (aus Chart.yaml)
5. **Deployment der Data Platform** mit dev-optimierten Werten (`ci/values-k3s-dev.yaml`)

---

## Dev-Konfiguration

Die Dev-Umgebung verwendet **reduzierte Ressourcen und einzelne Replicas**:

| Komponente | Produktion | Entwicklung |
|-----------|------------|-------------|
| PostgreSQL | Primary + Replica | Einzelnes Primary |
| Vault | 3 Replicas (HA) | 1 Replica |
| Keycloak | 2 Replicas + Infinispan | 1 Replica |
| MinIO | 4 Knoten (Verteilt) | 1 Knoten (Standalone) |
| Superset | 2 Replicas | 1 Replica |
| Trino | 1 Coordinator + 3 Worker | 1 Coordinator + 1 Worker |

**Alle Sicherheitsfeatures bleiben aktiv:**
- ✅ RBAC-Richtlinien
- ✅ NetworkPolicies (Deny-by-default)
- ✅ ExternalSecrets + Vault-Integration
- ✅ TLS bei kritischen Verbindungen
- ✅ Security Contexts (readOnlyRootFilesystem, runAsNonRoot)

Override-Datei: `ci/values-k3s-dev.yaml`

---

## Zugriff auf Services

### Option 1: Port Forwarding (Empfohlen)

```bash
# Ingress-Traffic weiterleiten
kubectl port-forward svc/ingress-nginx 80:80 443:443 -n ingress-nginx

# Dann Zugriff über:
# http://localhost/airflow
# http://localhost/bi
# http://localhost/catalog
# http://localhost/auth
```

### Option 2: Direktes Port Forwarding

```bash
# Airflow
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080

# Superset
kubectl port-forward svc/data-platform-superset 8088:8088

# OpenMetadata
kubectl port-forward svc/data-platform-openmetadata 8585:8585

# Keycloak
kubectl port-forward svc/data-platform-keycloak 8080:8080
```

### Option 3: kubectl describe

Pod-IPs abrufen:
```bash
kubectl get pods -o wide
```

---

## Überwachung

### Pod-Status prüfen

```bash
kubectl get pods
kubectl get pods -w  # Watch-Modus
```

### Logs anzeigen

```bash
kubectl logs <pod-name>
kubectl logs <pod-name> -f  # Folgen

# Beispiel:
kubectl logs data-platform-airflow-scheduler -f
```

### Ressourcennutzung

```bash
kubectl top pods
kubectl top nodes
```

### Pod beschreiben (Debug)

```bash
kubectl describe pod <pod-name>
kubectl describe pvc <pvc-name>
```

---

## Verifizierung

### Tests ausführen

```bash
helm test data-platform --timeout 5m
```

Tests überprüfen:
- PostgreSQL-Konnektivität
- MinIO-Erreichbarkeit
- Trino-Verfügbarkeit
- Keycloak-Gesundheit
- Vault-Gesundheit

### Manuelle Verifizierung

```bash
# Überprüfen, dass alle Services laufen
kubectl get svc

# Persistente Volumes überprüfen
kubectl get pvc

# Netzwerk-Richtlinien überprüfen
kubectl get networkpolicies

# Verifizieren, dass Secrets synchronisiert sind (ExternalSecrets)
kubectl get externalSecrets
kubectl get secrets
```

---

## Konfigurationsänderungen

### Ressourcen erhöhen (bei Speichermangel)

Editiere `ci/values-k3s-dev.yaml`:

```yaml
airflow:
  scheduler:
    resources:
      requests: { cpu: 500m, memory: 1Gi }  # Erhöhe von 250m/512Mi
      limits: { cpu: 1000m, memory: 2Gi }
```

Dann neu deployen:
```bash
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --wait --timeout 15m
```

### WSL2-Speicher erhöhen

Editiere `.wslconfig` im Windows Home-Verzeichnis:

```ini
[wsl2]
memory=16GB
processors=4
swap=2GB
```

Starte WSL2 dann neu:
```powershell
wsl --shutdown
```

---

## Cleanup

### Data Platform entfernen

```bash
helm uninstall data-platform
helm uninstall cert-manager -n cert-manager
helm uninstall ingress-nginx -n ingress-nginx
```

### Vollständiger Reset (WARNUNG: Löscht k3s)

```bash
# Auf WSL2:
k3s-uninstall.sh

# Oder neu installieren:
curl -sfL https://get.k3s.io | sh -
```

---

## Fehlerbehebung

### "Pod bleibt in Pending"

```bash
kubectl describe pod <pod-name>
# Ereignissektion für Grund überprüfen
```

**Häufige Ursachen:**
- Storage-Provisioning-Timeout (warten oder Speichergröße in `ci/values-k3s-dev.yaml` reduzieren)
- Ressourcenlimits überschritten (WSL2-Speicher erhöhen)
- Image-Pull-Fehler (in `kubectl logs` nachschauen)

### "ImagePullBackOff"

Überprüfe, ob die Image-Registry erreichbar ist:
```bash
kubectl describe pod <pod-name>
# Image-Feld und Pull-Fehler ansehen
```

### "Out of Memory" (OOMKilled)

Pods wurden wegen Speicherdruck abgetötet:
```bash
# Überprüfe, welcher Pod betroffen ist
kubectl describe pod <pod-name> | grep -i memory

# WSL2-Speicher erhöhen (siehe Konfigurationssektion)
# ODER Replicas/Ressourcen in ci/values-k3s-dev.yaml reduzieren
```

### "Helm Timeout"

Deployment dauert zu lange (normal auf WSL2):
```bash
# Timeout erhöhen
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --timeout 20m
```

Oder Fortschritt beobachten:
```bash
kubectl get pods -w
# Warte auf alle Pods im Status Running/Ready
```

### "ExternalSecrets werden nicht synchronisiert"

Überprüfe, dass Vault erreichbar und entsperrt ist:
```bash
kubectl get externalSecrets
kubectl describe externalsecret <secret-name>
```

Falls blockiert: Vault ist möglicherweise versiegelt. Manuelle Entsperrung erforderlich (Produktionsprozess, nicht in Dev).

### "Netzwerk-Konnektivitätsprobleme"

Überprüfe, dass NetworkPolicies nicht zu streng sind:
```bash
kubectl get networkpolicies
kubectl describe networkpolicy <policy-name>
```

Zum Debuggen: Temporär NetworkPolicies deaktivieren:
```yaml
networkPolicies:
  enabled: false
```

---

## Performance-Hinweise

⚠️ **k3s auf WSL2 ist nicht produktionsrepräsentativ:**
- Storage I/O langsamer als echtes Kubernetes
- Netzwerk-Latenz höher als bare metal
- Einige Operationen dauern 2-3x länger (normal, erwartet)

**Verwende für:**
- ✅ Entwicklung und Tests
- ✅ Feature-Validierung
- ✅ Integrationstests
- ✅ YAML-Syntax/Linting

**NICHT für:**
- ❌ Performance-Tests
- ❌ Load-Tests
- ❌ Validierung produktionsähnlicher Deployments

---

## Ressourcen

- **Hauptdokumentation:** `docs/architecture.md`, `docs/networking.md`, `docs/operations.md`
- **Setup-Anleitungen:** `docs/keycloak-setup.md`, `docs/metabase-setup.md`
- **Sicherheit:** `CLAUDE.md`, `docs/adrs/`
- **Tests:** `scripts/validate.sh`, `helm test`

---

## Hilfe bekommen

1. Überprüfe `docs/operations.md` auf häufige Probleme
2. Lies `CLAUDE.md` für Architekturentscheidungen
3. Führe `helm test data-platform` aus zur Verifizierung der Installation
4. Überprüfe Pod-Logs: `kubectl logs <pod-name>`
5. Frage Team oder überprüfe GitHub Issues
