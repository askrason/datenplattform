# TICKET-003: MinIO Sub-Chart + Hardening

## Ziel
MinIO als gehärteten, S3-kompatiblen Object Store deployen. Die Konfiguration
muss einen späteren Wechsel zu alternativen S3-kompatiblen Stores (Ceph, Garage,
Cloudflare R2) ohne Code-Änderungen an Consumers (Airflow, Trino, dbt) ermöglichen.

## Voraussetzungen
- TICKET-001 abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001, TICKET-002
Neue Dateien: values/minio.yaml,
  templates/networkpolicies/minio-netpol.yaml,
  templates/externalsecrets/minio-secrets.yaml,
  templates/tests/test-minio-connection.yaml
```

## Zu erstellende / zu ändernde Dateien

### 1. `values/minio.yaml`

**Modus:** `distributed` mit 4 Replicas (Minimum für Erasure Coding)

**Security:**
```yaml
podSecurityContext:
  <<: *defaultPodSecurityContext
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
securityContext:
  <<: *defaultSecurityContext
  # MinIO schreibt Daten auf das Volume, nicht ins Container-FS
  # readOnlyRootFilesystem bleibt true – Datenpfad ist gemountetes PVC
```

**Buckets (per `buckets`-Array vorkonfiguriert):**
- `airflow-logs` – Airflow Task Logs
- `airflow-dags` – DAG-Dateien (optional, falls GitSync nicht verwendet)
- `dbt-artifacts` – dbt Manifest, Catalog, Run Results
- `trino-spill` – Trino Spill-to-Disk
- `data-raw` – Landing Zone für Rohdaten
- `data-processed` – dbt-transformierte Daten
- `openmetadata-assets` – OM-spezifische Assets

**Policies (per `policies`-Array):**
- `airflow-policy`: read/write auf `airflow-logs/*`, `airflow-dags/*`, `dbt-artifacts/*`
- `trino-policy`: read/write auf `data-raw/*`, `data-processed/*`, read auf `trino-spill/*`
- `openmetadata-policy`: read auf alle Buckets (für Metadaten-Crawling)
- `admin-policy`: full access (nur für Admin-User)

**Users (per `users`-Array):**
- `airflow-svc` → `airflow-policy`
- `trino-svc` → `trino-policy`
- `openmetadata-svc` → `openmetadata-policy`

Alle Passwörter via `existingSecret` referenzieren.

**Ressourcen:**
```yaml
resources:
  requests: { cpu: "500m", memory: "1Gi" }
  limits:   { cpu: "2000m", memory: "4Gi" }
```

**Persistence:**
```yaml
persistence:
  enabled: true
  storageClass: "{{ .Values.global.storageClass }}"
  size: 500Gi
```

**TLS:** Intern kein TLS (Termination am Ingress).
MinIO Console via Ingress mit TLS.

**Hinweis S3-Austauschbarkeit:**
```yaml
# Alle Consumers verwenden ausschließlich:
# - Endpoint: http://{{ .Release.Name }}-minio:9000
# - Standard AWS S3 SDK / boto3 mit endpoint_url Override
# - KEIN MinIO-proprietäres SDK
# Wechsel zu Ceph/Garage: nur Endpoint + Credentials in Vault anpassen
```

**Metrics:** `metrics.serviceMonitor.enabled: true`

### 2. `templates/networkpolicies/minio-netpol.yaml`

Ingress auf Port 9000 (API) erlaubt von:
- Airflow (alle Pods)
- Trino (Coordinator + Worker)
- OpenMetadata
- dbt (= Airflow Worker Pods, bereits via Airflow-Selektor abgedeckt)

Ingress auf Port 9001 (Console) erlaubt von:
- Ingress Controller Namespace

Egress: nur DNS.

### 3. `templates/externalsecrets/minio-secrets.yaml`

Liest aus Vault (Vault-Pfad: `secret/data-platform/minio`):
- `root-user` → `minio-credentials.root-user`
- `root-password` → `minio-credentials.root-password`
- `airflow-secret-key` → `minio-credentials.airflow-secret-key`
- `trino-secret-key` → `minio-credentials.trino-secret-key`
- `openmetadata-secret-key` → `minio-credentials.openmetadata-secret-key`

> KORREKTUR: Pfad war zuvor `secret/data/data-platform/minio` angegeben.
> Konsistent mit der in TICKET-004 definierten Struktur und den übrigen
> ExternalSecret-Tickets (006–010) entfällt das zusätzliche `data/`-Segment.

### 4. `templates/tests/test-minio-connection.yaml`

Helm-Test der prüft:
- MinIO API Port 9000 erreichbar
- Alle 7 Buckets existieren (via `mc ls`)
- Alle Service-User können sich authentifizieren

## Akzeptanzkriterien

- [ ] MinIO deployed im Distributed-Mode (4 Pods)
- [ ] Alle 7 Buckets automatisch erstellt
- [ ] 3 Service-User mit korrekten Policies
- [ ] NetworkPolicy: nur Airflow, Trino, OM können auf Port 9000 zugreifen
- [ ] Kein proprietäres MinIO SDK in Konfigurationen
- [ ] `helm test` → test-minio-connection: Passed
- [ ] MinIO Console via Ingress erreichbar (Port 9001)
- [ ] `readOnlyRootFilesystem: true` (Daten auf PVC, nicht Container-FS)
