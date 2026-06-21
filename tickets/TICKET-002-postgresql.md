# TICKET-002: PostgreSQL Sub-Chart + Hardening

## Ziel
PostgreSQL als gehärtetes Sub-Chart konfigurieren. PostgreSQL dient als gemeinsamer
Metastore für Airflow, OpenMetadata, Superset und Metabase – mit separaten Datenbanken
pro Komponente und minimalen Rechten pro User.

## Voraussetzungen
- TICKET-001 abgeschlossen (Umbrella Chart Grundstruktur vorhanden)
- CLAUDE.md gelesen

## Hinweis (diese Überarbeitung)
- Es wird zusätzlich eine 6. Datenbank `keycloak` benötigt (siehe TICKET-010 und
  korrigierte `values.yaml`), nicht nur die 5 ursprünglich genannten.
- Bitnami-Repo-Migration beachten (CLAUDE.md, Known Issue #6) – betrifft das
  PostgreSQL-Chart selbst.

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001
Neue Dateien in diesem Ticket: values/postgresql.yaml,
  templates/networkpolicies/postgresql-netpol.yaml,
  templates/rbac/ (kein eigenes RBAC nötig für PG selbst),
  templates/externalsecrets/postgresql-secrets.yaml,
  templates/tests/test-postgresql-connection.yaml
```

## Zu erstellende / zu ändernde Dateien

### 1. `values/postgresql.yaml`

Konfiguriert das Bitnami PostgreSQL Chart mit:

**Architektur:** `replication` (primary + 1 read-replica)

**Security:**
```yaml
primary:
  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1001
    fsGroup: 1001
  containerSecurityContext:
    <<: *defaultSecurityContext
    # AUSNAHME: PostgreSQL schreibt WAL, pg_wal und temporäre Dateien
    readOnlyRootFilesystem: false
```

**Datenbanken:** Per `initdbScripts` folgende DBs und User anlegen:
- `airflow` / User: `airflow`
- `openmetadata` / User: `openmetadata`
- `superset` / User: `superset`
- `metabase` / User: `metabase`
- `keycloak` / User: `keycloak`

Jeder User hat NUR Rechte auf seine eigene Datenbank (GRANT, kein SUPERUSER).

**Secrets:** Alle Passwörter via `auth.existingSecret` referenzieren.
Kein Klartext. Secret-Name: `postgresql-credentials` (wird via ExternalSecret erstellt).

**Ressourcen (Primary):**
```yaml
resources:
  requests: { cpu: "500m", memory: "1Gi" }
  limits:   { cpu: "4000m", memory: "8Gi" }
```

**Persistence:**
```yaml
persistence:
  enabled: true
  storageClass: "{{ .Values.global.storageClass }}"
  size: 50Gi
```

**Metrics:** `metrics.enabled: true` (Prometheus-Exporter als Sidecar)

### 2. `templates/networkpolicies/postgresql-netpol.yaml`

NetworkPolicy die NUR folgende Ingress-Verbindungen auf Port 5432 erlaubt:

| Quelle | Label-Selektor |
|---|---|
| Airflow (alle Pods) | `app.kubernetes.io/name: airflow` |
| OpenMetadata | `app.kubernetes.io/name: openmetadata` |
| Superset | `app.kubernetes.io/name: superset` |
| Metabase | `app.kubernetes.io/name: metabase` |
| Keycloak | `app.kubernetes.io/name: keycloak` |
| Trino Coordinator | `app.kubernetes.io/name: trino, component: coordinator` |
| Prometheus (Metrics) | `app.kubernetes.io/name: prometheus` |

Egress: PostgreSQL darf nur auf DNS (Port 53) antworten. Keine ausgehenden
Verbindungen zu anderen Services.

### 3. `templates/externalsecrets/postgresql-secrets.yaml`

ExternalSecret-Ressource die folgende Keys aus Vault liest
(Vault-Pfad: `secret/data-platform/postgresql`):

```yaml
# Zu lesende Keys aus Vault:
# KORREKTUR: Pfad war zuvor "secret/data/data-platform/postgresql/...".
# Das "data/"-Segment entfällt hier, weil die ClusterSecretStore-Definition
# aus TICKET-004 bereits `version: "v2"` setzt – ESO ergänzt das KV-v2-
# "data/"-Segment intern selbst. Der remoteRef.key muss daher relativ zum
# in TICKET-004 definierten Pfad-Schema "secret/data-platform/<komponente>/<key>"
# angegeben werden, exakt wie in TICKET-004 für die anderen Komponenten.
- remoteRef.key: postgresql/root-password     → postgresql-credentials.postgres-password
- remoteRef.key: postgresql/airflow-password  → postgresql-credentials.airflow-password
- remoteRef.key: postgresql/openmetadata-password → postgresql-credentials.openmetadata-password
- remoteRef.key: postgresql/superset-password → postgresql-credentials.superset-password
- remoteRef.key: postgresql/metabase-password → postgresql-credentials.metabase-password
- remoteRef.key: postgresql/keycloak-password → postgresql-credentials.keycloak-password
```

Template nutzt `ClusterSecretStore` (wird in TICKET-004 erstellt).
Refresh-Interval: `1h`

### 4. `templates/tests/test-postgresql-connection.yaml`

Helm-Test-Pod der folgendes prüft:
- PostgreSQL Primary ist erreichbar (Port 5432)
- Alle 6 Datenbanken existieren (psql `\l`) – airflow, openmetadata, superset,
  metabase, keycloak (+ Default-DB `postgres`)
- Jeder App-User kann sich zu seiner DB verbinden

```yaml
# Test-Container nutzt postgres:16-alpine Image
# command: psql -h {{ postgresql-host }} -U postgres -c '\l'
# annotations: "helm.sh/hook": test
```

## Akzeptanzkriterien

- [ ] `helm lint` ohne Errors
- [ ] PostgreSQL deployed mit Replikation (primary + replica)
- [ ] 5 fachliche Datenbanken (airflow, openmetadata, superset, metabase, keycloak)
      mit je eigenem User
- [ ] Kein Klartext-Passwort in values.yaml oder templates/
- [ ] NetworkPolicy: nur explizit erlaubte Quellen erreichen Port 5432
- [ ] `helm test data-platform` → test-postgresql-connection Pod: Passed
- [ ] Metrics-Endpoint erreichbar (Port 9187)
- [ ] readOnlyRootFilesystem: false ist kommentiert mit Begründung
- [ ] Bitnami-OCI-Hinweis aus CLAUDE.md (Known Issue #6) berücksichtigt /
      Chart-Version verifiziert

## Nicht in diesem Ticket
- Vault-Setup (TICKET-004)
- ClusterSecretStore (TICKET-004) – ExternalSecret-Template kann vorbereitet werden,
  funktioniert erst nach TICKET-004
