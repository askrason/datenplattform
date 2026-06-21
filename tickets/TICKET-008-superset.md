# TICKET-008: Apache Superset Sub-Chart + Hardening

## Ziel
Apache Superset als primäres BI-Tool deployen – mit Trino als Haupt-Datenquelle,
Keycloak OIDC für SSO und gehärtetem Security-Kontext.

## Voraussetzungen
- TICKET-001 bis TICKET-004 abgeschlossen
- TICKET-006 (Trino) abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-007
Neue Dateien: values/superset.yaml,
  templates/networkpolicies/superset-netpol.yaml,
  templates/externalsecrets/superset-secrets.yaml
```

## Zu erstellende / zu ändernde Dateien

### 1. `values/superset.yaml`

**Security:**
```yaml
podSecurityContext:
  <<: *defaultPodSecurityContext
  runAsUser: 1000
  fsGroup: 1000
securityContext:
  <<: *defaultSecurityContext
  # AUSNAHME: Superset schreibt Flask-Sessions, Jinja-Cache, temporäre Chart-Exports
  readOnlyRootFilesystem: false
extraVolumes:
  - name: tmp
    emptyDir: {}
extraVolumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: home
    mountPath: /home/superset
volumes:
  - name: home
    emptyDir: {}
```

**Replicas:**
```yaml
replicaCount: 2   # HA für Webserver
```

**Ressourcen:**
```yaml
resources:
  requests: { cpu: "500m", memory: "1Gi" }
  limits:   { cpu: "2000m", memory: "4Gi" }
```

**Datenbankverbindung (PostgreSQL `superset` DB):**
```yaml
supersetNode:
  connections:
    db_host: "{{ .Release.Name }}-postgresql"
    db_port: 5432
    db_name: superset
    db_user: superset
    db_pass: ""   # via extraSecretEnv aus ExternalSecret
```

**SECRET_KEY (Flask):**
```yaml
extraSecretEnv:
  SUPERSET_SECRET_KEY:
    secretName: superset-credentials
    secretKey: secret-key
```

**Keycloak OIDC:**
```yaml
configOverrides:
  oidc_auth: |
    from flask_appbuilder.security.manager import AUTH_OAUTH
    AUTH_TYPE = AUTH_OAUTH
    OAUTH_PROVIDERS = [{
      "name": "keycloak",
      "icon": "fa-key",
      "token_key": "access_token",
      "remote_app": {
        "client_id": "superset",
        "client_secret": "<aus Secret>",
        "server_metadata_url": "https://{{ keycloak-url }}/realms/data-platform/.well-known/openid-configuration",
        "client_kwargs": {"scope": "openid email profile"},
      }
    }]
    AUTH_USER_REGISTRATION = True
    AUTH_USER_REGISTRATION_ROLE = "Gamma"   # Nur Lese-Rechte für neue User
    AUTH_ROLES_MAPPING = {
      "superset-admin": ["Admin"],
      "superset-analyst": ["Alpha"],
      "superset-viewer": ["Gamma"],
    }
    AUTH_ROLES_SYNC_AT_LOGIN = True
```

**Trino-Datenquelle (vorkonfiguriert via init-Script):**
```yaml
init:
  initscript: |
    #!/bin/bash
    superset db upgrade
    superset init
    # Trino-Datasource anlegen
    superset set-database-uri \
      --database-name "Trino (Data Platform)" \
      --uri "trino://trino-svc@{{ .Release.Name }}-trino:8080/iceberg"
```

**Celery Worker** (für asynchrone Queries und Reports):
```yaml
celeryWorker:
  enabled: true
  replicaCount: 2
  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1000
  securityContext:
    <<: *defaultSecurityContext
    readOnlyRootFilesystem: false
  resources:
    requests: { cpu: "500m", memory: "1Gi" }
    limits:   { cpu: "2000m", memory: "4Gi" }
```

**Redis** (für Celery Broker):
```yaml
redis:
  enabled: true   # Superset-internes Redis
  master:
    podSecurityContext:
      <<: *defaultPodSecurityContext
      runAsUser: 1000
    containerSecurityContext:
      <<: *defaultSecurityContext
    resources:
      requests: { cpu: "100m", memory: "256Mi" }
      limits:   { cpu: "500m", memory: "512Mi" }
```

**Ingress:**
```yaml
ingress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - host: "bi.{{ .Values.global.domain }}"
      paths: ["/"]
  tls:
    - secretName: superset-tls
      hosts: ["bi.{{ .Values.global.domain }}"]
```

### 2. `templates/networkpolicies/superset-netpol.yaml`

**Superset Webserver – Ingress:**
- Port 8088 vom Ingress Controller

**Superset + Celery Worker – Egress:**
- Trino Port 8080 (SQL-Queries)
- PostgreSQL Port 5432 (App-DB)
- Redis Port 6379 (Celery Broker, intern)
- Keycloak Port 8080/8443 (OIDC)
- DNS Port 53

### 3. `templates/externalsecrets/superset-secrets.yaml`

Liest aus Vault:
- `secret/data-platform/superset/secret-key` → `superset-credentials.secret-key`
- `secret/data-platform/postgresql/superset-password` → `superset-db-credentials.password`
- `secret/data-platform/superset/keycloak-client-secret` → `superset-oidc-credentials.client-secret`

## Akzeptanzkriterien

- [ ] Superset Webserver (2 Replicas) deployed und erreichbar
- [ ] Celery Worker für async Queries deployed
- [ ] Trino als Datenquelle vorkonfiguriert
- [ ] Keycloak OIDC: Login via SSO möglich
- [ ] Rollen-Mapping Keycloak → Superset konfiguriert
- [ ] Alle Secrets via ExternalSecret
- [ ] NetworkPolicy: nur Ingress → Port 8088, nur Superset → Trino/PG/Redis
- [ ] `readOnlyRootFilesystem: false` mit Kommentar
- [ ] `/tmp` und `/home/superset` als emptyDir gemountet
