# Data Platform Helm Chart – Project Context

## Projektübersicht

Dieses Repository enthält ein gehärtetes Umbrella Helm Chart für eine vollständige
Open-Source Data Platform auf Kubernetes. Das Chart folgt dem Hardening-Pattern des
BundesMessenger Helm Charts (opencode.de) und ist für den Einsatz in regulierten
Umgebungen ausgelegt.

---

## Stack-Komponenten

| Komponente | Version (Minimum) | Zweck |
|---|---|---|
| **MinIO** | 5.x (Operator Chart) | S3-kompatibler Object Store (später austauschbar gegen Ceph/Garage) |
| **Apache Airflow** | 3.x | Workflow-Orchestrierung (eigenständig, NICHT als OM-Dependency) |
| **dbt** | 1.9+ | SQL-Transformationen, läuft im Airflow-Worker-Image |
| **PostgreSQL** | 16.x (Bitnami / OCI) | Metastore für Airflow, OpenMetadata, Superset, Metabase |
| **Trino** | aktuell (trinodb/charts) | Distributed SQL Query Engine |
| **OpenMetadata** | 1.13+ | Data Catalog & Governance |
| **Apache Superset** | aktuell (apache/superset) | Primäres BI-Tool |
| **Metabase** | aktuell (Community Chart) | Ergänzendes Self-Service BI |
| **HashiCorp Vault** | aktuell | Secrets Management (Day-1-Komponente) |
| **Keycloak** | aktuell (Bitnami / OCI) | SSO / OIDC Identity Provider |
| **External Secrets Operator** | aktuell | Vault → K8s Secret Bridge |

### Infrastruktur-Voraussetzungen (außerhalb dieses Charts)
- Kubernetes 1.32+
- Helm 3.19+
- Ingress Controller (z.B. ingress-nginx) mit TLS-Terminierung
- cert-manager (für TLS-Zertifikate)
- StorageClass mit ReadWriteOnce-Support (Name: in `values.yaml` unter `global.storageClass` konfigurierbar)

---

## Architecture Decision Records (ADRs)

### ADR-001: Airflow eigenständig (nicht als OpenMetadata-Dependency)
**Entscheidung:** Airflow wird als eigenständiges Sub-Chart deployed.
**Begründung:** Volle Kontrolle über Airflow-Hardening und Custom-Image (mit dbt + OM-Ingestion).
OpenMetadata verbindet sich via REST API zum eigenständigen Airflow.
**Konsequenz:** OM-Chart wird mit `airflow.enabled: false` deployed. Airflow-REST-Endpoint
wird als ExternalService in OM konfiguriert.

### ADR-002: KubernetesExecutor für Airflow
**Entscheidung:** Airflow verwendet den KubernetesExecutor.
**Begründung:** Kein dauerhafter Worker-Pool, bessere Ressourcennutzung, native K8s-Integration.
**Konsequenz:** Airflow-Scheduler braucht RBAC-Rechte zum Erstellen/Löschen von Pods
im Airflow-Namespace. Worker-Pods erben Security-Kontext aus der Pod-Template-Config.

### ADR-003: External Secrets Operator + Vault (kein Plain-K8s-Secret)
**Entscheidung:** Alle Secrets werden über Vault verwaltet und via ESO als K8s Secrets bereitgestellt.
**Begründung:** Zentrale Secret-Verwaltung, Audit-Log, Dynamic Secrets für DB-Credentials.
**Konsequenz:** Kein Klartext in values.yaml. Alle apps referenzieren `existingSecret`-Felder.
ESO-ClusterSecretStore zeigt auf Vault. Vault verwendet Kubernetes Auth.

### ADR-004: Superset primär, Metabase ergänzend
**Entscheidung:** Superset ist das primäre BI-Tool. Metabase läuft parallel für einfachere Self-Service-Nutzung.
**Begründung:** Superset hat offizielles Chart, native Trino-Unterstützung und Keycloak-OIDC.
Metabase bietet bessere UX für nicht-technische Nutzer.
**Konsequenz:** Metabase OSS hat kein natives OIDC → oauth2-proxy als Sidecar für SSO.

### ADR-005: Keycloak als zentraler IdP
**Entscheidung:** Keycloak ist der einzige Identity Provider für alle Stack-Komponenten.
**Begründung:** Single Sign-On, zentrales User-Management, OIDC-Standard.
**Konsequenz:** Alle Apps werden mit OIDC-Client-Config deployed. Keycloak-Realm mit
vordefinierten Clients wird als ConfigMap verwaltet (GitOps-fähig).
Metabase-Ausnahme: SSO via oauth2-proxy (OSS-Limitation).

### ADR-006: Umbrella-Chart mit YAML-Anchors für Security-Defaults
**Entscheidung:** Ein Umbrella Chart mit gemeinsamen Security-Anchors (BundesMessenger-Pattern).
**Begründung:** Konsistente Hardening-Baseline ohne Duplikation. Anchors verhindern
versehentlich fehlende Security-Kontexte.
**Konsequenz:** Alle Komponenten-Overrides verwenden `<<: *defaultSecurityContext`.
Ausnahmen (z.B. readOnlyRootFilesystem: false für Webserver) sind explizit dokumentiert.

---

## Security Baseline (NON-NEGOTIABLE)

Folgende Security-Einstellungen gelten für ALLE Container ohne Ausnahme,
sofern nicht explizit mit Begründung in den Komponenten-Values überschrieben:

```yaml
# Container Security Context
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true      # Ausnahmen: siehe Komponenten-Kommentare
runAsNonRoot: true
capabilities:
  drop: [ALL]
seccompProfile:
  type: RuntimeDefault

# Pod Security Context
runAsNonRoot: true
fsGroupChangePolicy: OnRootMismatch
```

### Erlaubte Ausnahmen (müssen im Code kommentiert sein)
- `readOnlyRootFilesystem: false`: Airflow Webserver (Sessions), OpenMetadata (tmp files),
  Superset (tmp files), Metabase (tmp files), PostgreSQL (WAL), Keycloak (tmp)
- `runAsUser: 0`: NIEMALS erlaubt

### NetworkPolicy-Standard
- **Deny-by-default** für alle Namespaces
- Explizite Allow-Rules nur für dokumentierte Verbindungen
- Jede Komponente bekommt eine eigene NetworkPolicy-Template-Datei

### Resource Limits
- Resource `requests` UND `limits` müssen für JEDEN Container gesetzt sein
- Kein Container ohne CPU und Memory Limits

---

## Repository-Struktur

```
helm-chart/
├── CLAUDE.md                          # Diese Datei
├── Chart.yaml                         # Umbrella Chart Definition
├── Chart.lock                         # Dependency Lock
├── values.yaml                        # Globale Defaults + global-Block + Security-Anchors
├── values.schema.yaml                 # Validierungsschema
├── values.schema.json                 # JSON-Schema (aus YAML generiert)
├── .helmignore
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── architecture.md               # Architektur-Dokumentation
│   ├── adrs/                         # Architecture Decision Records
│   │   ├── ADR-001-airflow-standalone.md
│   │   └── ...
│   └── networking.md                 # NetworkPolicy-Übersicht
├── values/                           # Komponenten-spezifische Values
│   ├── vault.yaml
│   ├── external-secrets.yaml
│   ├── postgresql.yaml
│   ├── minio.yaml
│   ├── keycloak.yaml
│   ├── airflow.yaml
│   ├── trino.yaml
│   ├── openmetadata.yaml
│   ├── superset.yaml
│   └── metabase.yaml
├── templates/
│   ├── _helpers.tpl                  # Gemeinsame Template-Funktionen
│   ├── networkpolicies/
│   │   ├── default-deny.yaml         # Deny-all NetworkPolicy
│   │   ├── minio-netpol.yaml
│   │   ├── airflow-netpol.yaml
│   │   ├── postgresql-netpol.yaml
│   │   ├── trino-netpol.yaml
│   │   ├── openmetadata-netpol.yaml
│   │   ├── superset-netpol.yaml
│   │   ├── metabase-netpol.yaml
│   │   ├── vault-netpol.yaml
│   │   └── keycloak-netpol.yaml
│   ├── rbac/
│   │   ├── airflow-kubernetes-executor-rbac.yaml
│   │   └── vault-auth-rbac.yaml
│   ├── externalsecrets/
│   │   ├── cluster-secret-store.yaml
│   │   ├── airflow-secrets.yaml
│   │   ├── postgresql-secrets.yaml
│   │   ├── trino-secrets.yaml
│   │   ├── superset-secrets.yaml
│   │   ├── metabase-secrets.yaml
│   │   └── keycloak-secrets.yaml
│   └── tests/
│       ├── test-postgresql-connection.yaml
│       ├── test-minio-connection.yaml
│       └── test-airflow-health.yaml
├── files/
│   ├── keycloak-realm.json           # Keycloak Realm Export (GitOps)
│   └── airflow-connections.json      # Airflow Connection Definitions
└── scripts/
    ├── generate-schema.sh            # values.yaml → values.schema.json
    └── validate.sh                   # Lokale Validierung vor Commit
```

---

## Helm Chart Dependencies (Chart.yaml)

```yaml
dependencies:
  - name: vault            # helm.releases.hashicorp.com
  - name: external-secrets # charts.external-secrets.io
  - name: postgresql       # oci://registry-1.docker.io/bitnamicharts (s. Known Issue #6)
  - name: minio             # helm.min.io
  - name: keycloak          # oci://registry-1.docker.io/bitnamicharts (s. Known Issue #6)
  - name: airflow           # airflow.apache.org (Airflow 3.x)
  - name: trino             # trinodb.github.io/charts
  - name: openmetadata      # helm.open-metadata.org
  - name: superset          # apache.github.io/superset
  - name: metabase          # Community Chart (Repo vor TICKET-009 verifizieren)
```

---

## Coding Conventions

### YAML-Anchor-Pattern (BundesMessenger-Style)
```yaml
# In values.yaml – ganz oben, vor allen Komponenten-Configs
x-security-context: &defaultSecurityContext
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault

x-pod-security: &defaultPodSecurityContext
  runAsNonRoot: true
  fsGroupChangePolicy: OnRootMismatch

# Verwendung:
someComponent:
  securityContext:
    <<: *defaultSecurityContext
  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1000   # Komponentenspezifische UID
    fsGroup: 1000
```

### Kommentarpflicht für Ausnahmen
```yaml
webserver:
  securityContext:
    <<: *defaultSecurityContext
    # AUSNAHME: readOnlyRootFilesystem deaktiviert, da Airflow Webserver
    # Flask-Sessions und temporäre Template-Dateien in /tmp schreibt.
    # Mitigiert durch: emptyDir für /tmp, kein Netzwerk-Write-Access.
    readOnlyRootFilesystem: false
```

### Secret-Referenzierung
```yaml
# RICHTIG: Referenz auf existierendes Secret (erstellt via ExternalSecret)
auth:
  existingSecret: "{{ .Release.Name }}-postgresql-credentials"
  existingSecretPasswordKey: "password"

# FALSCH: Kein Klartext in values.yaml
auth:
  password: "mein-passwort"  # ← NIEMALS
```

### Ressourcen-Template
```yaml
resources:
  requests:
    cpu: "250m"      # Immer setzen
    memory: "512Mi"  # Immer setzen
  limits:
    cpu: "1000m"     # Immer setzen
    memory: "2Gi"    # Immer setzen
```

---

## Verbindungsmatrix (für NetworkPolicies)

| Von → Nach | Port | Protokoll | Zweck |
|---|---|---|---|
| Airflow → PostgreSQL | 5432 | TCP | Airflow Metastore |
| Airflow → MinIO | 9000 | TCP | DAG-Artefakte, dbt-Output |
| Airflow → Vault | 8200 | TCP | Secret Sync (via ESO) |
| Trino → MinIO | 9000 | TCP | S3-Catalog-Queries |
| Trino → PostgreSQL | 5432 | TCP | PostgreSQL-Catalog |
| OpenMetadata → Trino | 8080 | TCP | Metadaten-Crawling |
| OpenMetadata → Airflow | 8080 | TCP | Pipeline-Metadaten (REST API) |
| OpenMetadata → MinIO | 9000 | TCP | Storage-Metadaten |
| OpenMetadata → PostgreSQL | 5432 | TCP | OM Metastore |
| Superset → Trino | 8080 | TCP | SQL-Queries |
| Metabase → Trino | 8080 | TCP | SQL-Queries |
| Metabase → PostgreSQL | 5432 | TCP | Metabase App-DB |
| Superset → PostgreSQL | 5432 | TCP | Superset App-DB |
| Alle → Keycloak | 8080/8443 | TCP | OIDC Token Validation |
| ESO → Vault | 8200 | TCP | Secret Sync |
| Ingress → Airflow Webserver | 8080 | TCP | UI |
| Ingress → Superset | 8088 | TCP | UI |
| Ingress → Metabase | 3000 | TCP | UI |
| Ingress → OpenMetadata | 8585 | TCP | UI |
| Ingress → MinIO Console | 9001 | TCP | Admin UI |
| Ingress → Keycloak | 8080 | TCP | SSO UI + OIDC Endpoints |

---

## Wichtige Einschränkungen & Known Issues

1. **Metabase OIDC**: Metabase OSS unterstützt kein natives OIDC.
   Lösung: oauth2-proxy als Sidecar-Container.

2. **OpenMetadata ↔ Airflow**: OM deployed standardmäßig eigenes Airflow.
   Dieses Chart disabled das (`airflow.enabled: false` in OM-Config) und
   konfiguriert stattdessen den externen Airflow-REST-Endpoint.

3. **Trino + MinIO**: Trino benötigt einen Hive Metastore oder Iceberg REST Catalog
   für strukturierte Tabellen-Metadaten. Für den Einstieg: File-basierter Metastore.
   Mittelfristig: Apache Polaris oder Nessie als Iceberg Catalog evaluieren.

4. **MinIO-Austauschbarkeit**: Alle S3-Verbindungen verwenden ausschließlich den
   S3-kompatiblen Endpoint (kein MinIO-proprietäres SDK). Wechsel zu Ceph/Garage
   erfordert nur Endpoint-URL- und Credential-Änderungen.

5. **Vault HA-Mode**: Vault sollte im HA-Mode mit mindestens 3 Replicas deployed werden.
   Vault Unseal muss separat gehandhabt werden (Vault Auto Unseal via Cloud KMS oder
   manueller Unseal-Prozess dokumentieren).

6. **Bitnami-Repo-Migration (seit Aug. 2025)**: Bitnami hat das klassische
   Helm-Repository `charts.bitnami.com` zugunsten einer OCI-Registry
   (`oci://registry-1.docker.io/bitnamicharts/<chart>`) abgelöst. Ältere,
   versionsgepinnte Container-Images wurden nach `bitnamilegacy` verschoben
   und erhalten KEINE Updates mehr; im kostenlosen Free-Tier sind i.d.R. nur
   noch "latest"-Tags der "Secure Images" verfügbar. Betroffen sind in diesem
   Chart **PostgreSQL (TICKET-002)** und **Keycloak (TICKET-010)**. Vor dem
   Deployment:
   - `helm show chart oci://registry-1.docker.io/bitnamicharts/postgresql`
     bzw. `.../keycloak` prüfen und die exakte Version in `Chart.yaml` pinnen.
   - Image-Tags ggf. explizit überschreiben (Legacy-Tag oder eigenes Mirror),
     sonst droht `ImagePullBackOff` bei Rollouts/Scaling.
   - Für produktiven Einsatz in regulierter Umgebung: Bitnami Secure Images
     (kommerziell) oder Alternativ-Charts (z.B. CloudNativePG für PostgreSQL,
     Codecentric- oder offizielles Keycloak-Operator-Chart) evaluieren.

---

## Entwicklungs-Workflow

### Lokale Validierung
```bash
# Vor jedem Commit ausführen:
./scripts/validate.sh

# Entspricht:
helm dependency update
helm lint . --values values.yaml
helm template . --values values.yaml | kubectl --dry-run=client apply -f -
helm unittest .
```

### Schema-Generierung
```bash
# Nach Änderungen an values.yaml:
./scripts/generate-schema.sh
# Generiert values.schema.json aus values.schema.yaml
```

### Test-Deployment (lokales Cluster)
```bash
# Kind-Cluster für lokale Tests:
kind create cluster --config ci/kind-config.yaml
helm install data-platform . \
  --values values.yaml \
  --values values/postgresql.yaml \
  --set global.storageClass=standard
```
