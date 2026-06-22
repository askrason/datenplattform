# Schnelleinstieg (Quick Start)

Deployment der Data Platform in 10 Minuten. Für detailliertere Einrichtung siehe `docs/installation-de.md`.

---

## Voraussetzungen (5 min)

```bash
# Tools überprüfen
helm version      # 3.19+
kubectl version   # 1.32+
git --version

# Cluster vorbereiten
kubectl create namespace data-platform

# Helm Repositories hinzufügen
helm repo add vault https://helm.releases.hashicorp.com
helm repo add apache https://airflow.apache.org
helm repo add trinodb https://trinodb.github.io/charts
helm repo update
```

---

## Klonen & Deployen (5 min)

```bash
# 1. Repository klonen
git clone https://github.com/askrason/datenplattform.git
cd datenplattform

# 2. Domain aktualisieren (KRITISCH!)
vim values.yaml
# Ändere: global.domain = "deine-domain.com"

# 3. Dependencies abrufen
helm dependency update

# 4. Validieren
./scripts/validate.sh

# 5. Installieren
helm install data-platform . \
  --namespace data-platform \
  --values values.yaml \
  --wait --timeout 20m

# 6. Status überprüfen
kubectl get pods -n data-platform
```

---

## Services aufrufen (Nach DNS/TLS bereit)

```bash
# Services sind erreichbar unter:
# - https://airflow.deine-domain.com         (Admin: admin/airflow)
# - https://superset.deine-domain.com        (Admin: admin/admin)
# - https://metabase.deine-domain.com        (OAuth via Keycloak)
# - https://openmetadata.deine-domain.com    (Admin: admin/admin)
# - https://keycloak.deine-domain.com/admin  (Admin: admin/changeme)

# Oder Port-Forwarding für schnellen Zugriff:
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080 -n data-platform &
# http://localhost:8080
```

---

## Essenzielle Post-Deploy-Schritte

```bash
# 1. Vault entsperren (falls Shamir verwendet)
kubectl port-forward svc/data-platform-vault 8200:8200 -n data-platform &
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# 2. Keycloak Admin-Passwort ändern
kubectl port-forward svc/data-platform-keycloak 8080:80 -n data-platform &
# http://localhost:8080/admin → admin / changeme → Passwort ändern!

# 3. Überprüfen, dass alle Services gesund sind
kubectl get pods -n data-platform
# Alle sollten Running/Ready sein
```

---

## Fehlerbehebung

```bash
# Pod-Status überprüfen
kubectl describe pod <pod-name> -n data-platform

# Logs ansehen
kubectl logs <pod-name> -n data-platform

# Überprüfen, ob ExternalSecrets synchronisiert sind
kubectl get externalsecret -n data-platform

# Port-Forwarding zum Debuggen
kubectl port-forward svc/data-platform-postgresql 5432:5432 -n data-platform
kubectl port-forward svc/data-platform-vault 8200:8200 -n data-platform
```

---

## Nächste Schritte

- Lesen Sie `docs/installation-de.md` für Production-Setup
- Siehe `docs/operations.md` für tägliche Operationen
- Siehe `CLAUDE.md` für Architektur & ADRs
- Führen Sie `./scripts/validate.sh` vor jedem Commit aus

---

**Fragen? Siehe:**
- Vollständige Installationsanleitung: `docs/installation-de.md`
- Fehlerbehebung: `docs/operations.md`
- Architektur: `docs/architecture.md`
