# TICKET-007: OpenMetadata Sub-Chart + Airflow-Integration

## Ziel
OpenMetadata als Data Catalog deployen – eigenständig, ohne eigenes Airflow
(ADR-001). Konfiguration des REST-API-Connectors zum eigenständigen Airflow-Deployment
(TICKET-005) sowie Keycloak-OIDC-Anbindung.

## Voraussetzungen
- TICKET-001 bis TICKET-006 abgeschlossen
- CLAUDE.md gelesen (insbesondere ADR-001)

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-006
Neue Dateien: values/openmetadata.yaml,
  templates/networkpolicies/openmetadata-netpol.yaml,
  templates/externalsecrets/openmetadata-secrets.yaml
```

## Wichtiger Hinweis (ADR-001)
Das OpenMetadata Helm Chart deployed standardmäßig eine eigene Airflow-Instanz
als Dependency. Das wird in diesem Ticket DEAKTIVIERT:
```yaml
openmetadata:
  # Das OM-eigene Airflow deaktivieren (wir nutzen das eigenständige aus TICKET-005)
  airflow:
    enabled: false
```
OpenMetadata verbindet sich stattdessen per REST-API zum Airflow-Service aus TICKET-005.

## Zu erstellende / zu ändernde Dateien

### 1. `values/openmetadata.yaml`

**Airflow-Dependency deaktivieren:**
```yaml
openmetadata:
  enabled: true
  # OM-eigenes Airflow deaktivieren (ADR-001)
  airflow:
    enabled: false
```

**Security:**
```yaml
podSecurityContext:
  <<: *defaultPodSecurityContext
  runAsUser: 1000
  fsGroup: 1000
securityContext:
  <<: *defaultSecurityContext
  # AUSNAHME: OM schreibt temporäre Dateien und Logs
  readOnlyRootFilesystem: false
extraVolumes:
  - name: tmp
    emptyDir: {}
extraVolumeMounts:
  - name: tmp
    mountPath: /tmp
resources:
  requests: { cpu: "500m", memory: "1Gi" }
  limits:   { cpu: "2000m", memory: "4Gi" }
```

**Datenbankverbindung (PostgreSQL aus TICKET-002):**
```yaml
config:
  database:
    host: "{{ .Release.Name }}-postgresql"
    port: 5432
    driverClass: "org.postgresql.Driver"
    dbScheme: "postgresql"
    dbUseSSL: false
    databaseName: openmetadata
    existingSecret: openmetadata-db-credentials
    existingSecretPasswordKey: password
```

**Airflow-Connector-Konfiguration (zeigt auf eigenständigen Airflow aus TICKET-005):**
```yaml
config:
  pipelineServiceClientConfig:
    enabled: true
    className: "org.openmetadata.service.clients.pipeline.airflow.AirflowRESTClient"
    apiEndpoint: "http://{{ .Release.Name }}-airflow-webserver:8080"
    metadataApiEndpoint: "http://{{ .Release.Name }}-openmetadata:8585/api"
    verifySSL: false
    secretsManagerCredentials:
      existingSecret: openmetadata-airflow-credentials
      existingSecretKey: api-token
```

**Keycloak OIDC:**
```yaml
config:
  authentication:
    provider: "custom-oidc"
    publicKeyUrls:
      - "https://{{ keycloak-url }}/realms/data-platform/protocol/openid-connect/certs"
    authority: "https://{{ keycloak-url }}/realms/data-platform"
    clientId: "openmetadata"
    callbackUrl: "https://{{ om-url }}/callback"
    enableSelfSignup: false
  authorizer:
    initialAdmins:
      - "admin"     # Keycloak-Username des ersten Admin-Users
    principalDomain: "{{ .Values.global.domain }}"
```

**Elasticsearch/OpenSearch (OM nutzt ES für Suche):**
```yaml
# OpenMetadata benötigt Elasticsearch oder OpenSearch.
# Optionen:
# A) OpenSearch als zusätzliche Chart-Dependency (empfohlen)
# B) OM-eingebautes Elasticsearch (einfacher, weniger Kontrolle)
# Entscheidung: Option B für den Start (OM-eigenes ES), später migrierbar.
elasticsearch:
  enabled: true   # OM-eigenes Elasticsearch
```

**Ingress:**
```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  hosts:
    - host: "catalog.{{ .Values.global.domain }}"
      paths: [{ path: /, pathType: Prefix }]
  tls:
    - secretName: openmetadata-tls
      hosts: ["catalog.{{ .Values.global.domain }}"]
```

### 2. `templates/networkpolicies/openmetadata-netpol.yaml`

**Ingress:**
- Port 8585 (OM API + UI) vom Ingress Controller
- Port 8585 von Airflow (REST-API-Calls von Airflow zu OM für Metadaten-Push)

**Egress:**
- PostgreSQL Port 5432 (Metastore)
- Airflow Webserver Port 8080 (Pipeline-Metadaten via REST API)
- MinIO Port 9000 (Storage-Metadaten crawlen)
- Trino Port 8080 (SQL-Metadaten crawlen)
- Keycloak Port 8080/8443 (OIDC)
- Elasticsearch Port 9200 (Search Index, OM-intern)
- DNS Port 53

### 3. `templates/externalsecrets/openmetadata-secrets.yaml`

Liest aus Vault:
- `secret/data-platform/postgresql/openmetadata-password` → `openmetadata-db-credentials.password`
- `secret/data-platform/openmetadata/airflow-api-token` → `openmetadata-airflow-credentials.api-token`
- `secret/data-platform/openmetadata/keycloak-client-secret` → `openmetadata-oidc-credentials.client-secret`

### 4. `docs/openmetadata-connectors.md`

Dokumentation der manuellen Schritte nach dem ersten Deployment:

```markdown
## OpenMetadata Connector-Setup (einmalig nach Deployment)

### 1. Airflow-Pipeline-Service konfigurieren
In der OM-UI unter Settings → Services → Pipeline Services:
- Service Type: Airflow
- Connection: http://{{ airflow-webserver-service }}:8080
- Metadata Ingestion: via DAG (DAG wird automatisch in Airflow erstellt)

### 2. Trino-Datenbank-Service konfigurieren
Settings → Services → Database Services:
- Service Type: Trino
- Connection: trino://{{ trino-service }}:8080
- Catalogs: minio, iceberg, postgresql

### 3. MinIO-Storage-Service konfigurieren
Settings → Services → Storage Services:
- Service Type: S3 (S3-kompatibel)
- Endpoint: http://{{ minio-service }}:9000
```

## Akzeptanzkriterien

- [ ] OpenMetadata deployed (kein eigenes Airflow als Dependency)
- [ ] OM-UI erreichbar via Ingress
- [ ] Datenbankverbindung zu PostgreSQL (`openmetadata` DB) funktioniert
- [ ] Airflow-REST-Connector konfiguriert (zeigt auf TICKET-005 Airflow)
- [ ] Keycloak-OIDC konfiguriert
- [ ] `docs/openmetadata-connectors.md` vorhanden mit Einrichtungsanleitung
- [ ] NetworkPolicy: OM kann Airflow, Trino, MinIO, PG erreichen
- [ ] Alle Secrets via ExternalSecret
