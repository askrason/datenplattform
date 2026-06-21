# TICKET-005: Airflow 3 Sub-Chart + dbt-Integration

## Ziel
Apache Airflow 3 als eigenständiges, gehärtetes Sub-Chart deployen –
mit KubernetesExecutor, Custom-Image (Airflow + dbt + OpenMetadata-Ingestion)
und Keycloak-OIDC-Anbindung. dbt läuft als Python-Library im Airflow-Worker-Image,
nicht als eigenständiger Service.

## Voraussetzungen
- TICKET-001 bis TICKET-004 abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-004
Neue Dateien: values/airflow.yaml,
  templates/networkpolicies/airflow-netpol.yaml,
  templates/rbac/airflow-kubernetes-executor-rbac.yaml,
  templates/externalsecrets/airflow-secrets.yaml,
  templates/tests/test-airflow-health.yaml,
  files/airflow-dockerfile/Dockerfile,
  files/airflow-dockerfile/requirements.txt
```

## Architektur-Entscheidungen (ADR-001, ADR-002)
- Airflow ist EIGENSTÄNDIG – NICHT als OpenMetadata-Dependency
- KubernetesExecutor: Scheduler spawnt Worker-Pods dynamisch
- OpenMetadata verbindet sich via REST-API zu diesem Airflow (konfiguriert in TICKET-007)

## Zu erstellende / zu ändernde Dateien

### 1. `files/airflow-dockerfile/Dockerfile`

Custom Airflow Image mit dbt und OpenMetadata-Ingestion:

```dockerfile
# syntax=docker/dockerfile:1
ARG AIRFLOW_VERSION=3.0.2
ARG PYTHON_VERSION=3.12
FROM apache/airflow:${AIRFLOW_VERSION}-python${PYTHON_VERSION}

# Als Root für System-Packages, dann zurück zu airflow-User
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*
USER airflow

COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
```

### 2. `files/airflow-dockerfile/requirements.txt`

```
# dbt Core + Adapter
dbt-core>=1.9.0,<2.0.0
dbt-trino>=1.9.0
dbt-postgres>=1.9.0

# OpenMetadata Ingestion (für DAGs die Metadaten pushen)
openmetadata-ingestion>=1.13.0

# Airflow Providers
apache-airflow-providers-cncf-kubernetes>=10.0.0
apache-airflow-providers-postgres>=5.0.0
apache-airflow-providers-amazon>=8.0.0  # S3Hook für MinIO

# Utilities
pendulum>=3.0.0
```

### 2. `values/airflow.yaml`

**Executor:** `KubernetesExecutor`

**Images:**
```yaml
images:
  airflow:
    repository: "{{ .Values.global.imageRegistry }}/airflow-dbt"
    tag: "3.0.2-python3.12"
    pullPolicy: IfNotPresent
```

**Security:**
```yaml
podSecurityContext:
  <<: *defaultPodSecurityContext
  runAsUser: 50000
  runAsGroup: 50000
  fsGroup: 50000

securityContext:
  <<: *defaultSecurityContext

webserver:
  securityContext:
    <<: *defaultSecurityContext
    # AUSNAHME: Airflow Webserver schreibt Flask-Sessions und Jinja-Template-Cache
    readOnlyRootFilesystem: false
  replicas: 2
  resources:
    requests: { cpu: "500m", memory: "1Gi" }
    limits:   { cpu: "2000m", memory: "2Gi" }

scheduler:
  resources:
    requests: { cpu: "500m", memory: "1Gi" }
    limits:   { cpu: "2000m", memory: "4Gi" }
  # Kein Persistent Volume für Logs – Logs gehen zu MinIO
  logGroomerSidecar:
    enabled: true
```

**KubernetesExecutor Pod-Template:**
```yaml
workers:
  podTemplate:
    spec:
      securityContext:
        runAsUser: 50000
        runAsGroup: 50000
        fsGroup: 50000
        runAsNonRoot: true
      containers:
        - name: base
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
            seccompProfile:
              type: RuntimeDefault
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: dbt-profiles
              mountPath: /home/airflow/.dbt
      volumes:
        - name: tmp
          emptyDir: {}
        - name: dbt-profiles
          secret:
            secretName: dbt-profiles
```

**Datenbankverbindung:**
```yaml
data:
  metadataConnection:
    user: airflow
    db: airflow
    host: "{{ .Release.Name }}-postgresql"
    port: 5432
    existingSecret: airflow-db-credentials
    existingSecretKey: password
```

**Logs → MinIO (S3):**
```yaml
logs:
  persistence:
    enabled: false
  remote:
    enabled: true
    provider: "aws"   # boto3 S3-kompatibel
    conn_id: "aws_default"
    base_log_folder: "s3://airflow-logs/logs"
    bucket_name: "airflow-logs"
    # endpoint_url wird via Connection/Env-Var gesetzt → MinIO-Endpunkt
```

**OIDC / Keycloak:**
```yaml
webserverConfig: |
  from airflow.www.security import AirflowSecurityManager
  from flask_appbuilder.security.manager import AUTH_OAUTH

  AUTH_TYPE = AUTH_OAUTH
  AUTH_USER_REGISTRATION = True
  AUTH_USER_REGISTRATION_ROLE = "Viewer"

  OAUTH_PROVIDERS = [{
    "name": "keycloak",
    "icon": "fa-key",
    "token_key": "access_token",
    "remote_app": {
      "client_id": "airflow",
      "client_secret": "<aus Secret>",
      "server_metadata_url": "https://{{ keycloak-url }}/realms/data-platform/.well-known/openid-configuration",
      "api_base_url": "https://{{ keycloak-url }}/realms/data-platform/protocol/openid-connect",
      "request_token_params": {"scope": "openid email profile"},
    }
  }]
```

**Secrets:**
```yaml
extraSecrets:
  airflow-fernet-key:
    stringData: {}  # via ExternalSecret befüllt
env:
  - name: AIRFLOW__CORE__FERNET_KEY
    valueFrom:
      secretKeyRef:
        name: airflow-credentials
        key: fernet-key
  - name: AIRFLOW__WEBSERVER__SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: airflow-credentials
        key: webserver-secret-key
```

### 3. `templates/rbac/airflow-kubernetes-executor-rbac.yaml`

RBAC für den KubernetesExecutor – minimale Rechte:

```yaml
# ServiceAccount: airflow-scheduler
# Role (Namespace-scoped, KEIN ClusterRole):
#   - pods: get, list, watch, create, delete, patch
#   - pods/log: get
#   - pods/exec: create (für debugging, optional)
# RoleBinding: airflow-scheduler → Role
```

### 4. `templates/networkpolicies/airflow-netpol.yaml`

**Airflow Webserver – Ingress:**
- Port 8080 vom Ingress Controller

**Airflow Scheduler – Egress:**
- PostgreSQL Port 5432 (Metastore)
- MinIO Port 9000 (Logs + DAG-Artefakte)
- K8s API Server Port 443 (KubernetesExecutor spawnt Pods)
- Keycloak Port 8080/8443 (OIDC Token Validation)

**Airflow Worker Pods – Egress:**
- PostgreSQL Port 5432 (dbt-postgres Adapter)
- MinIO Port 9000 (dbt-artifacts, Logs)
- Trino Port 8080 (dbt-trino Adapter)
- OpenMetadata Port 8585 (Metadaten-Push via openmetadata-ingestion)

**OpenMetadata → Airflow Webserver:**
- Port 8080 (REST API für Pipeline-Metadaten) – Ingress erlaubt

### 5. `templates/externalsecrets/airflow-secrets.yaml`

Liest aus Vault (Vault-Pfad: `secret/data-platform/airflow`):
- `fernet-key` → `airflow-credentials.fernet-key`
- `webserver-secret-key` → `airflow-credentials.webserver-secret-key`
- `db-password` (aus postgresql-Pfad) → `airflow-db-credentials.password`
- `minio-access-key` → `airflow-minio-credentials.access-key`
- `minio-secret-key` → `airflow-minio-credentials.secret-key`
- `keycloak-client-secret` → `airflow-oidc-credentials.client-secret`

> KORREKTUR: Pfad war zuvor `secret/data/data-platform/airflow` angegeben.
> Konsistent mit TICKET-004 entfällt das zusätzliche `data/`-Segment.

### 6. `templates/tests/test-airflow-health.yaml`

Helm-Test prüft:
- Airflow Webserver Health Endpoint (`/health`) antwortet 200
- Scheduler ist `healthy`
- Datenbankverbindung OK

## Akzeptanzkriterien

- [ ] Airflow 3 deployed (Webserver, Scheduler, kein statischer Worker)
- [ ] KubernetesExecutor konfiguriert + RBAC vorhanden
- [ ] Custom Image (airflow-dbt) referenziert
- [ ] Keycloak OIDC konfiguriert (auch wenn KC noch nicht deployed)
- [ ] Logs werden zu MinIO geschrieben (S3-Remote-Logging)
- [ ] Alle Secrets via ExternalSecret (kein Klartext)
- [ ] NetworkPolicy: Worker-Pods dürfen Trino, PG, MinIO, OM erreichen
- [ ] `helm test` → test-airflow-health: Passed
- [ ] Dockerfile + requirements.txt als Vorlage vorhanden
- [ ] Worker-Pods nutzen Security-Kontext aus Pod-Template
- [ ] `readOnlyRootFilesystem: false` für Webserver mit Kommentar
