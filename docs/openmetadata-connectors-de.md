# OpenMetadata Connector-Setup

## Überblick

Nach dem Deployment von OpenMetadata (TICKET-007) müssen die Konnektoren zu den Datenquellen manuell konfiguriert werden. Dies ist eine **einmalige Aufgabe** pro Umgebung.

---

## 1. Airflow Pipeline-Service Konfigurieren

### Voraussetzungen
- Airflow-Deployment ist laufen (TICKET-005)
- Airflow Admin-User existiert
- API-Token wurde generiert und in Vault hinterlegt

### Schritte

1. **Login zu OpenMetadata**
   ```
   https://catalog.<your-domain>/
   ```

2. **Zu Settings → Services → Pipeline Services navigieren**

3. **"Add Service" auswählen**
   - Service Type: `Airflow`
   - Service Name: `airflow-primary`
   - Connection:
     - Host: `{{ .Release.Name }}-airflow-webserver`
     - Port: `8080`
     - Number of Status Retries: `3`
     - Secrets Manager Credentials: Nicht erforderlich (REST-API ohne Auth)

4. **Speichern und testen**
   - OM zeigt "Connection successful" → OK

5. **Airflow-Ingestion DAG automatisch einspielen**
   - Nach der Connector-Konfiguration wird automatisch ein DAG in Airflow erstellt
   - DAG Name: `openmetadata_ingestion_airflow`
   - Scheduler lädt den DAG automatisch ein

### Troubleshooting

| Problem | Lösung |
|---------|--------|
| `Connection refused` auf Port 8080 | Airflow-Service läuft nicht oder Namespace-Issue. `kubectl get svc -n default` prüfen |
| DAG wird nicht erstellt | ESO-Secret für Airflow-API-Token fehlt. `kubectl get secrets` prüfen |

---

## 2. Trino Database Service Konfigurieren

### Schritte

1. **Settings → Services → Database Services**

2. **"Add Service" auswählen**
   - Service Type: `Trino`
   - Service Name: `trino-primary`
   - Connection:
     - Host: `{{ .Release.Name }}-trino`
     - Port: `8080`
     - Catalogs: Alle Kataloge aktivieren (`minio`, `iceberg`, `postgresql`)

3. **Speichern**
   - OM erstellt automatisch Ingestion DAGs für Metadaten-Crawling

### Katalog-Mappings

OpenMetadata erkennt automatisch:
- **Catalog `minio`** (Hive): Tabellen aus MinIO S3
- **Catalog `iceberg`**: Iceberg-Tabellen (dbt-Trino Integration)
- **Catalog `postgresql`**: Native PostgreSQL-Tabellen

---

## 3. MinIO Storage Service Konfigurieren

### Schritte

1. **Settings → Services → Storage Services**

2. **"Add Service" auswählen**
   - Service Type: `S3`
   - Service Name: `minio-primary`
   - Connection:
     - Access Key: MinIO Trino Service-User (aus Vault)
     - Secret Key: MinIO Trino Service-User (aus Vault)
     - Endpoint: `http://{{ .Release.Name }}-minio:9000`
     - Bucket Name: Leer (OM crawlt alle Buckets automatisch)
     - Schema Location: `s3://data-raw/` und `s3://data-processed/`

3. **Speichern**

### Buckets

Folgende Buckets werden von OM gecrawlt:
- `data-raw/` (von Airflow populiert, via Trino Hive-Katalog)
- `data-processed/` (dbt-Output, via Trino Iceberg-Katalog)

---

## 4. PostgreSQL Database Service Konfigurieren (Optional)

Falls PostgreSQL-Tabellen in OpenMetadata katalogisiert werden sollen (z.B. operative Airflow-DB):

1. **Settings → Services → Database Services**

2. **"Add Service" auswählen**
   - Service Type: `Postgres`
   - Service Name: `postgresql-primary`
   - Connection:
     - Host: `{{ .Release.Name }}-postgresql`
     - Port: `5432`
     - Database: Leer (OM crawlt alle DBs)
     - Username: `trino` (Read-only User aus TICKET-002)
     - Password: Aus Vault

3. **Speichern**

---

## 5. Keycloak OIDC Validierung

Nach TICKET-010 (Keycloak-Deployment) sollte die OIDC-Authentifizierung automatisch funktionieren:

1. **Logout aus OpenMetadata**
2. **Neuer Login**
   - Redirect zu Keycloak
   - Keycloak Credentials eingeben
   - Redirect zurück zu OM mit OIDC Token

Falls Token-Fehler auftreten:
- Keycloak-Client-Secret in Vault überprüfen (ExternalSecret muss synced sein)
- OM-Pod Logs prüfen: `kubectl logs -f <om-pod>`

---

## 6. Ingestion DAGs automatisieren

OpenMetadata erstellt automatisch Ingestion DAGs in Airflow:

```
openmetadata_ingestion_airflow
openmetadata_ingestion_trino
openmetadata_ingestion_minio
```

Diese DAGs können in Airflow-UI über Zeitplan angepasst werden:
- Standard: täglich um 00:00 UTC
- Anpassung: `Admin → DAGs → DAG-Details → Schedule`

---

## 7. Metadaten-Browsing

Nach erfolgreicher Ingestion sind Metadaten in OM verfügbar:

**Data Assets:**
```
Assets → Schemas → Tables → Columns
```

**Data Lineage:**
```
Governance → Lineage → DAG-Name
```

**Search:**
```
Search-Bar oben → Query eingeben → Treffer filtern nach Type (Table, Schema, Dataset)
```

---

## Troubleshooting-Checkliste

| Komponente | Check | Befehl |
|------------|-------|--------|
| OM Pods | Running? | `kubectl get pods -l app.kubernetes.io/name=openmetadata` |
| OM Service | Resolvierbar? | `kubectl get svc openmetadata` |
| DB-Connection | Reachable? | `kubectl exec -it <om-pod> -- psql -h <pg-host> -U openmetadata -d openmetadata` |
| Airflow-API | Erreichbar? | `curl http://<airflow-webserver>:8080/api/v1/health` |
| Trino-Connector | OK? | OM UI → Services → Trino → "Test Connection" |
| ESO Secrets | Synced? | `kubectl get externalSecrets` |

---

## Weitere Ressourcen

- OM Dokumentation: https://docs.open-metadata.org/
- Airflow Ingestion: https://docs.open-metadata.org/connectors/ingestion/workflows/metadata/airflow
- Trino Connector: https://docs.open-metadata.org/connectors/database/trino
