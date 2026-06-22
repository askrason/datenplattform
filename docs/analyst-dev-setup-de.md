# Data Analyst Entwicklungsumgebungs-Setup

## Überblick

Schnelle lokale Entwicklungsumgebung für **Query- und BI-Entwicklung**.

- **Komponenten:** Trino, Superset, Metabase, PostgreSQL
- **NICHT enthalten:** Vault, Keycloak, Airflow, OpenMetadata (nicht relevant für BI-Entwicklung)
- **Ressourcen:** 6-8 GB RAM
- **Setup-Zeit:** 4-5 Minuten

## Schnellstart

```bash
cd datenplattform
chmod +x scripts/setup-analyst-dev.sh
./scripts/setup-analyst-dev.sh
```

## Was ist enthalten

| Komponente | Zweck | Anmerkungen |
|-----------|-------|-----------|
| **Trino** | Verteilte SQL-Query-Engine | Fokus dieser Umgebung |
| **Superset** | Primäres BI-Tool für Dashboards | Apache Superset mit nativer Trino-Unterstützung |
| **Metabase** | Sekundäres BI-Tool (Self-Service Analytics) | Community Edition, leichtgewichtig |
| **PostgreSQL** | Data Warehouse (Beispieldaten) | Einzelne Replica |

## Zugriff auf Services

### Trino UI

```bash
kubectl port-forward svc/data-platform-trino 8080:8080
# Dann: http://localhost:8080/ui/
```

**Zugriff:** Keine Authentifizierung erforderlich

### Superset

```bash
kubectl port-forward svc/data-platform-superset 8088:8088
# Dann: http://localhost:8088
```

**Login:** admin / admin (Standard)

**Setup:**
1. Trino als Datenbankverbindung hinzufügen
2. Datasets aus Queries erstellen
3. Dashboards erstellen

### Metabase

```bash
kubectl port-forward svc/data-platform-metabase 3000:3000
# Dann: http://localhost:3000
```

**Erstes Login:** Folge Setup-Assistenten
- Datenbank hinzufügen: Trino
- Questions/Dashboards erstellen

## Häufige Aufgaben

### Trino Query testen

**Option 1: Trino UI**
```
http://localhost:8080/ui/
```

**Option 2: CLI**
```bash
# Installiere trino CLI
trino --server http://localhost:8080 --catalog minio --schema default

> SELECT * FROM my_table LIMIT 5;
```

### Dashboard in Superset erstellen

1. Port-Forward zu Superset
2. Mit admin/admin anmelden
3. Trino-Datenbank hinzufügen:
   - Host: `data-platform-trino` (wenn Zugriff von Pod)
   - Oder `localhost:8080` (wenn Port-Forwarding)
4. Dataset aus SQL Query erstellen
5. Visualisierung erstellen
6. Zu Dashboard hinzufügen

### Report in Metabase erstellen

1. Port-Forward zu Metabase
2. Trino-Datenbank via Setup-Assistenten hinzufügen
3. Neue "Question" erstellen
4. SQL schreiben oder Query Builder nutzen
5. Speichern und teilen

### Verfügbare Schemas/Tabellen überprüfen

```bash
# Mit PostgreSQL zur Metadaten-Abfrage verbinden
kubectl exec -it data-platform-postgresql-0 -- psql -U postgres

# Oder Trino abfragen
trino> SHOW CATALOGS;
trino> SHOW SCHEMAS FROM postgresql;
```

## Überwachung

```bash
# Pod-Status
kubectl get pods -w

# Logs
kubectl logs <pod-name> -f

# Ressourcennutzung
kubectl top pods
```

## Cleanup

```bash
# Deployment entfernen
helm uninstall data-platform

# Persistente Daten entfernen
kubectl delete pvc --all
```

## Wichtige Hinweise

⚠️ **NICHT produktionsreif:**
- Kein Vault/Keycloak = keine Authentifizierung/Sicherheit
- Kein Airflow = keine Datenaufnahme/ETL
- Kein OpenMetadata = keine Governance
- Einzelne Replicas = keine HA
- Für produktionsähnliche Tests verwende `values-k3s-dev.yaml`

✅ **Gut für:**
- SQL-Query-Entwicklung
- Dashboard/Report-Design
- BI-Exploration
- Testen von Superset/Metabase-Konfigurationen

## Performance-Hinweise

- Queries auf Beispieldaten: schnell
- Komplexe Queries auf großen Datensätzen: möglicherweise langsam (einzelner Trino-Worker)
- Dashboard-Rendering: glatt (einzelne Superset-Replica)

## Fehlerbehebung

### Pod startet nicht

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Trino-Verbindung fehlgeschlagen

Überprüfe, dass Trino läuft:
```bash
kubectl get pods | grep trino
kubectl logs <trino-pod>
```

### Speichermangel

WSL2-Speicher erhöhen:
```ini
# .wslconfig
[wsl2]
memory=8GB
```

### Kann nicht von Superset auf Trino zugreifen

Wenn interne Hostname-Nutzung:
- Superset → Trino: `http://data-platform-trino:8080`
- Nicht: `http://localhost:8080`

## Siehe auch

- Engineer Dev (DAG/dbt): `docs/engineer-dev-setup.md`
- Full-Stack Dev: `docs/k3s-dev-setup.md`
- Architektur: `docs/architecture.md`
