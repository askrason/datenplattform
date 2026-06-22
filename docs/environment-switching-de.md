# Anleitung zum Umschalten zwischen Umgebungen

Schnelles Umschalten zwischen verschiedenen Entwicklungsumgebungen auf demselben k3s-Cluster.

## Drei Umgebungen

Alle drei teilen sich dieselben **PostgreSQL**- und **MinIO**-Datenquellen via Persistent Volumes.

### 1. Full-Stack Dev (Produktionsähnlich)

```bash
./scripts/switch-to-full-stack.sh
```

**Enthält:** Alles (Vault, Keycloak, Airflow, Trino, BI-Tools, etc.)
**RAM:** 8-16 GB
**Setup:** ~10 Minuten
**Best für:** Vollständige Integrationstests, Sicherheit/Auth-Tests

### 2. Engineer Dev (DAG-Entwicklung)

```bash
./scripts/switch-to-engineer.sh
```

**Enthält:** Airflow, Trino, PostgreSQL, MinIO
**RAM:** 4-6 GB
**Setup:** ~3-4 Minuten
**Best für:** DAG/dbt-Entwicklung, schnelle Iteration

### 3. Analyst Dev (BI-Entwicklung)

```bash
./scripts/switch-to-analyst.sh
```

**Enthält:** Trino, Superset, Metabase, PostgreSQL
**RAM:** 6-8 GB
**Setup:** ~4-5 Minuten
**Best für:** Query/Dashboard-Entwicklung

---

## Gemeinsame Daten

Alle drei Umgebungen nutzen **dieselben** Persistent Volumes:

```
PostgreSQL (PVC):  data-platform-postgresql-data
MinIO (PVC):       data-platform-minio-data
```

**Ablauf:**
```
Engineer Dev
  ↓ (erstellt Daten in PostgreSQL/MinIO)
  ↓
Umschalten auf Analyst Dev
  ↓ (sieht dieselben Daten)
  ↓
Zurückschalten zu Engineer Dev
  ↓ (Daten sind noch da!)
```

---

## Typischer Workflow

### Montag: Engineer arbeitet an DAG

```bash
./scripts/switch-to-engineer.sh

# DAG entwickeln
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080
# http://localhost:8080
# → DAG erstellen/testen
# → DAG ausführen, Daten landen in MinIO/PostgreSQL
```

### Dienstag: Analyst analysiert die Daten

```bash
./scripts/switch-to-analyst.sh

# Dieselben Daten, andere Tools
kubectl port-forward svc/data-platform-superset 8088:8088
# http://localhost:8088
# → Dashboard aus Engineers Daten erstellen
```

### Mittwoch: Engineer aktualisiert DAG

```bash
./scripts/switch-to-engineer.sh

# Dieselben PostgreSQL/MinIO-Daten
# → DAG basierend auf Analyst-Feedback aktualisieren
# → DAG mit aktualisierter Logik neu ausführen
```

---

## Hinter den Kulissen

Jedes Skript führt folgendes durch:

```bash
# 1. Überprüfe, ob data-platform Release existiert
helm list | grep data-platform

# 2. Aktualisiere Abhängigkeiten (falls nötig)
helm dependency update

# 3. Upgrade/Install mit rollenspezifischen Values
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-ROLE-dev.yaml \
  --wait --timeout 10m

# 4. Zeige laufende Pods
kubectl get pods --no-headers | grep data-platform

# 5. Drucke Zugriffanweisungen
```

**Schlüssel:** `helm upgrade` berührt PVCs nicht, daher persistieren Daten.

---

## Datenpersistenz

### Was persistiert (bleibt)

```
✅ PostgreSQL-Daten
✅ MinIO-Buckets und Objekte
✅ Beliebige manuelle Konfiguration in PVCs
```

### Was ändert sich (setzt zurück)

```
❌ Pod-Status (wird neu gestartet)
❌ In-Memory-Caches
❌ Temporäre Dateien in emptyDir-Volumes
```

---

## Cleanup

### Alles entfernen

```bash
# Entferne Helm Release (PVCs verwaist, nicht gelöscht)
helm uninstall data-platform

# Lösche PVCs (DATENVERLUST - Vorsicht!)
kubectl delete pvc --all
```

### Behalte Daten, entferne Pods

```bash
# Nur deinstallieren (PVCs bleiben)
helm uninstall data-platform

# Später: mit Daten wiederherstellen
./scripts/switch-to-engineer.sh
# PostgreSQL/MinIO-Daten sind noch da!
```

---

## Fehlerbehebung

### "Release nicht gefunden"

Nur beim ersten Mal, Skript installiert automatisch.

### "Pod pending"

Warte länger oder überprüfe Logs:
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### "Verbindung zu PostgreSQL/MinIO abgelehnt"

Stelle sicher, dass alte PVCs nicht interferieren:
```bash
kubectl get pvc
kubectl get pv
```

### Speichermangel

WSL2 erhöhen:
```ini
# .wslconfig
[wsl2]
memory=16GB
```

---

## Erweitert: Ein Release, drei Configs

Anstatt umzuschalten, könntest du alle drei als separate Releases ausführen:

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

**Aber:** Jeder würde separate PostgreSQL/MinIO brauchen (oder via Namespaces teilen), daher ist Umschalten sauberer.

---

## Siehe auch

- Engineer Setup: `docs/engineer-dev-setup.md`
- Analyst Setup: `docs/analyst-dev-setup.md`
- Full-Stack Setup: `docs/k3s-dev-setup.md`
