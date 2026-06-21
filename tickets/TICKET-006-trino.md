# TICKET-006: Trino Sub-Chart + Hardening

## Ziel
Trino als gehärteten Distributed SQL Query Engine deployen mit Coordinator + Worker,
vorkonfigurierten Katalogen für MinIO (S3/Hive) und PostgreSQL, und minimalen
Netzwerk-Rechten.

## Voraussetzungen
- TICKET-001 bis TICKET-004 abgeschlossen
- TICKET-002 (PostgreSQL) und TICKET-003 (MinIO) abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-005
Neue Dateien: values/trino.yaml,
  templates/networkpolicies/trino-netpol.yaml,
  templates/externalsecrets/trino-secrets.yaml
```

## Zu erstellende / zu ändernde Dateien

### 1. `values/trino.yaml`

**Replicas:**
- Coordinator: 1 (kein HA – Coordinator ist stateless genug für Restart)
- Worker: 3

**Security:**
```yaml
coordinator:
  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1000
    fsGroup: 1000
  securityContext:
    <<: *defaultSecurityContext
    # AUSNAHME: Trino Coordinator schreibt Query-History und temporäre Dateien
    readOnlyRootFilesystem: false
  resources:
    requests: { cpu: "1000m", memory: "2Gi" }
    limits:   { cpu: "4000m", memory: "8Gi" }

worker:
  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1000
    fsGroup: 1000
  securityContext:
    <<: *defaultSecurityContext
    readOnlyRootFilesystem: false  # Trino Worker Spill-to-Disk
  resources:
    requests: { cpu: "2000m", memory: "4Gi" }
    limits:   { cpu: "8000m", memory: "16Gi" }
  extraVolumes:
    - name: spill
      emptyDir: {}
  extraVolumeMounts:
    - name: spill
      mountPath: /tmp/trino-spill
```

**Kataloge:**

```yaml
catalogs:
  # S3/MinIO-Katalog via Hive Connector
  # Für strukturierte Tabellen (Iceberg/ORC/Parquet) auf MinIO
  minio.properties: |
    connector.name=hive
    hive.metastore=file
    hive.metastore.catalog.dir=s3://data-raw/
    hive.s3.endpoint=http://{{ .Release.Name }}-minio:9000
    hive.s3.path-style-access=true
    hive.s3.ssl.enabled=false
    hive.s3.aws-credentials-provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider
    # Credentials werden via Env-Vars injiziert (aus Secret)

  # Iceberg-Katalog (zukunftssicher, empfohlen für dbt-trino)
  iceberg.properties: |
    connector.name=iceberg
    iceberg.catalog.type=hive_metastore
    hive.metastore=file
    hive.metastore.catalog.dir=s3://data-processed/
    hive.s3.endpoint=http://{{ .Release.Name }}-minio:9000
    hive.s3.path-style-access=true
    hive.s3.ssl.enabled=false

  # PostgreSQL-Katalog (direkter Zugriff auf operative DBs)
  postgresql.properties: |
    connector.name=postgresql
    connection-url=jdbc:postgresql://{{ .Release.Name }}-postgresql:5432/
    connection-user=${ENV:TRINO_PG_USER}
    connection-password=${ENV:TRINO_PG_PASSWORD}
    # Zugriff auf alle DBs über diesen einen Katalog-Eintrag
    # Schema-Selektion erfolgt im SQL: SELECT * FROM postgresql.airflow.dag_run
```

**JVM Config (Coordinator):**
```yaml
jvm:
  maxHeapSize: "6G"
  gcMethod:
    type: "UseG1GC"
    g1:
      heapRegionSize: "32M"
```

**Trino Config:**
```yaml
config:
  # Spill-to-Disk für große Queries
  spillEnabled: true
  spillPath: /tmp/trino-spill
  # Query-Limits (DoS-Schutz)
  query.max-memory: "5GB"
  query.max-memory-per-node: "2GB"
  query.max-total-memory-per-node: "3GB"
```

**Auth:**
Trino lauscht intern ohne Auth (NetworkPolicy schränkt Zugriff ein).
Für Produktion: Trino OIDC/OAuth2 mit Keycloak (mittlerer Aufwand,
kann in TICKET-010 ergänzt werden).

```yaml
# Kommentar in values.yaml:
# Trino Auth via OIDC (Keycloak) ist vorbereitet aber initial deaktiviert.
# Aktivierung: trino.auth.oauth2.enabled: true nach TICKET-010 (Keycloak).
```

**Credentials via Env-Vars (aus Secret):**
```yaml
extraEnv:
  - name: AWS_ACCESS_KEY_ID        # MinIO Trino Service-User
    valueFrom:
      secretKeyRef:
        name: trino-minio-credentials
        key: access-key
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: trino-minio-credentials
        key: secret-key
  - name: TRINO_PG_USER
    valueFrom:
      secretKeyRef:
        name: trino-pg-credentials
        key: username
  - name: TRINO_PG_PASSWORD
    valueFrom:
      secretKeyRef:
        name: trino-pg-credentials
        key: password
```

### 2. `templates/networkpolicies/trino-netpol.yaml`

**Coordinator – Ingress Port 8080 erlaubt von:**
- Superset (`app.kubernetes.io/name: superset`)
- Metabase (`app.kubernetes.io/name: metabase`)
- OpenMetadata (`app.kubernetes.io/name: openmetadata`)
- Airflow Worker Pods (`component: worker`)
- Trino Worker Pods (interne Cluster-Kommunikation)
- Ingress Controller (für Trino UI, optional)

**Worker – Ingress:**
- Nur vom Coordinator (interne Cluster-Kommunikation)

**Coordinator + Worker – Egress:**
- MinIO Port 9000
- PostgreSQL Port 5432
- Trino-intern (Coordinator ↔ Worker, Port 8080 + 8081)
- DNS Port 53

### 3. `templates/externalsecrets/trino-secrets.yaml`

Liest aus Vault:
- `secret/data-platform/minio/trino-access-key` → `trino-minio-credentials.access-key`
- `secret/data-platform/minio/trino-secret-key` → `trino-minio-credentials.secret-key`
- `secret/data-platform/postgresql/trino-password` → `trino-pg-credentials.password`
- (PostgreSQL-User für Trino anlegen in TICKET-002 `initdbScripts` ergänzen)

## Akzeptanzkriterien

- [ ] Trino Coordinator + 3 Worker deployed und `healthy`
- [ ] Kataloge `minio` (Hive), `iceberg` und `postgresql` vorhanden
- [ ] `SHOW CATALOGS` in Trino gibt alle 3 zurück
- [ ] Query gegen MinIO-Daten: `SELECT 1` ohne Fehler
- [ ] Query gegen PostgreSQL: `SELECT * FROM postgresql.public.information_schema.tables` erfolgreich
- [ ] NetworkPolicy: nur Superset, Metabase, OM, Airflow-Worker können Port 8080 erreichen
- [ ] Spill-Verzeichnis korrekt gemountet (emptyDir)
- [ ] Alle Credentials via ExternalSecret
- [ ] Worker-Pods `readOnlyRootFilesystem: false` mit Kommentar
