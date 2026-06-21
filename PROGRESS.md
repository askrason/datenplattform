# Data Platform Helm Chart – Progress Report

**Stand: 21. Juni 2026**

## Übersicht

Dieses Dokument dokumentiert den aktuellen Implementierungsstand des gehärteten Umbrella Helm Charts für die Open-Source Data Platform.

## Abgeschlossene Tickets ✅

### TICKET-001: Umbrella Chart Grundstruktur
**Status:** ✅ VOLLSTÄNDIG

Erstellte Dateien:
- `Chart.yaml` – Umbrella Chart mit 10 Dependencies
- `values.yaml` – Globale Security-Defaults (YAML-Anchors), global-Block
- `values.schema.yaml` – JSON-Schema für Validierung
- `values.schema.json` – Auto-generierte JSON-Version
- `templates/_helpers.tpl` – 7 Template-Funktionen
- `templates/networkpolicies/default-deny.yaml` – Deny-all-Baseline
- `.helmignore` – Ignorierte Dateien für Helm-Packaging
- `scripts/validate.sh` – Pre-Commit Validierungsskript
- `scripts/generate-schema.sh` – YAML→JSON Schema-Konvertierung
- `README.md` – Projektdokumentation
- `values.yaml` – Global `networkPolicies.enabled: true` hinzugefügt

**Akzeptanzkriterien erfüllt:**
- ✅ helm dependency update läuft
- ✅ helm lint ohne Errors
- ✅ helm template produziert valides YAML
- ✅ YAML-Anchors funktionieren
- ✅ NetworkPolicy default-deny vorhanden
- ✅ Kein Klartext-Secret in values.yaml
- ✅ Alle Komponenten haben enabled-Flags

---

### TICKET-004: Vault + External Secrets Operator
**Status:** ✅ VOLLSTÄNDIG

Erstellte Dateien:
- `values/vault.yaml` – Vault im HA-Modus (3 Replicas, Raft-Storage), IPC_LOCK für mlock
- `values/external-secrets.yaml` – ESO mit installCRDs, Security-Context für Operator/Webhook/CertController
- `templates/externalsecrets/cluster-secret-store.yaml` – ClusterSecretStore mit Kubernetes Auth
- `templates/rbac/vault-auth-rbac.yaml` – ClusterRole für TokenReview (Vault ↔ K8s)
- `templates/networkpolicies/vault-netpol.yaml` – Restrict Port 8200/8201
- `docs/vault-setup.md` – Komplette Initialisierungsanleitung (init, unseal, auth-setup, secret-befüllung)

**Akzeptanzkriterien erfüllt:**
- ✅ Vault im HA-Modus (3 Replicas, Raft)
- ✅ ESO deployed und läuft
- ✅ ClusterSecretStore vault-backend erstellt
- ✅ vault-setup.md vollständig
- ✅ RBAC für ESO-Vault-Auth vorhanden
- ✅ NetworkPolicy: nur ESO und Vault-interne Pods auf Port 8200
- ✅ IPC_LOCK mit Kommentar
- ✅ vault.injector.enabled: false (nutzen ESO)
- ✅ Vault-UI via Ingress konfigurierbar

**Vault Secret-Struktur (Konvention):**
```
secret/data-platform/
├── postgresql/ (root-, airflow-, openmetadata-, superset-, metabase-, keycloak-password)
├── minio/ (root-user, root-password, airflow-, trino-, openmetadata-secret-key)
├── airflow/ (fernet-key, webserver-secret-key)
├── keycloak/ (admin-password, db-password)
└── [weitere in TICKET-006+ befüllt]
```

---

### TICKET-002: PostgreSQL Sub-Chart + Hardening
**Status:** ✅ VOLLSTÄNDIG

Erstellte Dateien:
- `values/postgresql.yaml` – Replication (Primary + 1 Read-Replica), 6 DBs (airflow, openmetadata, superset, metabase, keycloak, postgres), Least-Privilege-User
- `templates/networkpolicies/postgresql-netpol.yaml` – Strikte Zugriffskontrolle (nur Airflow, OM, Superset, Metabase, Keycloak, Trino, Prometheus)
- `templates/externalsecrets/postgresql-secrets.yaml` – ESO lädt 6 Passwörter aus Vault
- `templates/tests/test-postgresql-connection.yaml` – Helm-Test für DB-Connectivity

**Akzeptanzkriterien erfüllt:**
- ✅ PostgreSQL im Replication-Mode (Primary + Replica)
- ✅ 6 Datenbanken + User mit Least-Privilege
- ✅ Kein Klartext in values/templates
- ✅ NetworkPolicy restriktiv (explizite Allow-Rules)
- ✅ Helm-Test für Verbindungen
- ✅ Metrics aktiviert (Prometheus-Exporter)
- ✅ readOnlyRootFilesystem: false mit Begründung

---

### TICKET-003: MinIO Sub-Chart + Hardening
**Status:** ✅ VOLLSTÄNDIG

Erstellte Dateien:
- `values/minio.yaml` – Distributed Mode (4 Pods mit Erasure Coding), 7 Buckets, 3 Service-User mit IAM-Policies
- `templates/networkpolicies/minio-netpol.yaml` – Port 9000 (API) von Airflow/Trino/OM, Port 9001 (Console) vom Ingress-Controller
- `templates/externalsecrets/minio-secrets.yaml` – ESO lädt Root + Service-User Secret-Keys
- `templates/tests/test-minio-connection.yaml` – Helm-Test für Bucket-Existenz

**Buckets (automatisch erstellt):**
- airflow-logs
- airflow-dags
- dbt-artifacts
- trino-spill
- data-raw
- data-processed
- openmetadata-assets

**Service-User:**
- airflow-svc → airflow-policy (read/write auf airflow-*, dbt-artifacts)
- trino-svc → trino-policy (read/write auf data-raw, data-processed, trino-spill)
- openmetadata-svc → openmetadata-policy (read auf alle Buckets)

**Akzeptanzkriterien erfüllt:**
- ✅ MinIO Distributed (4 Pods)
- ✅ 7 Buckets + 3 Service-User
- ✅ NetworkPolicy restriktiv
- ✅ Kein proprietäres MinIO SDK (Standard S3 SDK)
- ✅ Helm-Test für Bucket-Verification
- ✅ MinIO Console via Ingress
- ✅ readOnlyRootFilesystem: true (Daten auf PVC)

**S3-Austauschbarkeit:**
- Alle Consumers verwenden nur Standard AWS S3 SDK
- Endpoint: `http://{{ .Release.Name }}-minio:9000`
- Wechsel zu Ceph/Garage/R2: nur Endpoint + Vault-Credentials anpassen

---

### TICKET-005: Airflow 3 Sub-Chart + dbt-Integration
**Status:** ✅ VOLLSTÄNDIG

Erstellte Dateien:
- `files/airflow-dockerfile/Dockerfile` – Custom Airflow 3.0.2 Image mit dbt + OpenMetadata-Ingestion
- `files/airflow-dockerfile/requirements.txt` – Python-Dependencies (dbt-core, dbt-trino, dbt-postgres, openmetadata-ingestion, Providers)
- `values/airflow.yaml` – KubernetesExecutor, Keycloak OIDC, S3-Remote-Logging, Pod-Template mit Security-Context
- `templates/rbac/airflow-kubernetes-executor-rbac.yaml` – Namespace-scoped Role für Pod Management (create/delete/patch)
- `templates/networkpolicies/airflow-netpol.yaml` – Scheduler/Worker Netzwerk-Zugriff (PG, MinIO, Trino, OM, Keycloak, K8s API)
- `templates/externalsecrets/airflow-secrets.yaml` – 4 ExternalSecrets (Core Secrets, DB, MinIO, OIDC)
- `templates/tests/test-airflow-health.yaml` – Helm-Test für Health-Endpoint + Scheduler-Status

**Architektur-Highlights:**
- **ADR-001**: Airflow eigenständig (nicht als OM-Dependency)
- **ADR-002**: KubernetesExecutor mit dynamischen Worker-Pods (kein statischer Pool)
- **dbt-Integration**: Läuft als Python-Library im Custom Image
- **Keycloak OIDC**: SSO für Webserver (AUTH_OAUTH mit Keycloak Provider)
- **S3-Remote-Logging**: Alle Task-Logs zu MinIO (s3://airflow-logs/logs)

**ExternalSecrets:**
1. airflow-credentials: fernet-key, webserver-secret-key
2. airflow-db-credentials: PostgreSQL airflow-password
3. airflow-minio-credentials: MinIO access/secret keys
4. airflow-oidc-credentials: Keycloak client-secret

**Akzeptanzkriterien erfüllt:**
- ✅ Airflow 3 deployed (Webserver, Scheduler, KubernetesExecutor)
- ✅ Custom Image mit dbt + OM-Ingestion
- ✅ Keycloak OIDC konfiguriert
- ✅ S3-Remote-Logging aktiviert
- ✅ Secrets via ExternalSecret
- ✅ NetworkPolicy für Worker-Zugriff
- ✅ Helm-Test vorhanden
- ✅ Pod-Template mit Security-Context
- ✅ readOnlyRootFilesystem: false für Webserver (mit Begründung)

---

## In Vorbereitung / Nächste Schritte

### TICKET-006: Trino Sub-Chart + Hardening
**Status:** 🔄 TODO

Geplante Dateien:
- `values/trino.yaml` – Coordinator + Worker, Catalogs (hive/minio, postgresql, iceberg)
- `templates/networkpolicies/trino-netpol.yaml`
- `templates/externalsecrets/trino-secrets.yaml`
- `templates/tests/test-trino-connectivity.yaml`

### TICKET-007: OpenMetadata Sub-Chart
**Status:** 🔄 TODO

Geplante Dateien:
- `values/openmetadata.yaml` – Config für OM 1.13+, Vault-Integration, Airflow REST-Endpoint
- `templates/externalsecrets/openmetadata-secrets.yaml`
- `templates/networkpolicies/openmetadata-netpol.yaml`
- `templates/tests/test-openmetadata-health.yaml`

### TICKET-008: Apache Superset Sub-Chart
**Status:** 🔄 TODO

Geplante Dateien:
- `values/superset.yaml` – Keycloak OIDC, Trino Connection
- `templates/externalsecrets/superset-secrets.yaml`
- `templates/networkpolicies/superset-netpol.yaml`

### TICKET-009: Metabase Sub-Chart + oauth2-proxy
**Status:** 🔄 TODO

Geplante Dateien:
- `values/metabase.yaml` – Community Chart + oauth2-proxy Sidecar für Keycloak SSO
- `templates/externalsecrets/metabase-secrets.yaml`
- `templates/networkpolicies/metabase-netpol.yaml`

### TICKET-010: Keycloak Sub-Chart + Realm-Config
**Status:** 🔄 TODO

Geplante Dateien:
- `values/keycloak.yaml` – Realm-Import, Clients, 2 Replicas
- `files/keycloak-realm.json` – GitOps Realm-Export
- `templates/externalsecrets/keycloak-secrets.yaml`
- `templates/networkpolicies/keycloak-netpol.yaml`

### TICKET-011: Integration Tests
**Status:** 🔄 TODO

Geplante Dateien:
- `templates/tests/test-integration-airflow-to-trino.yaml`
- `templates/tests/test-integration-minio-s3.yaml`

### TICKET-012: Dokumentation & Deployment-Guides
**Status:** 🔄 TODO

Geplante Dateien:
- `docs/architecture.md`
- `docs/deployment-guide.md`
- `docs/troubleshooting.md`

---

## Dateistruktur (aktuell)

```
helm-chart/
├── Chart.yaml ✅
├── Chart.lock
├── values.yaml ✅
├── values.schema.yaml ✅
├── values.schema.json ✅
├── .helmignore ✅
├── README.md ✅
├── PROGRESS.md (diese Datei)
│
├── values/
│   ├── vault.yaml ✅
│   ├── external-secrets.yaml ✅
│   ├── postgresql.yaml ✅
│   ├── minio.yaml ✅
│   ├── airflow.yaml ✅
│   ├── trino.yaml 🔄
│   ├── keycloak.yaml 🔄
│   ├── openmetadata.yaml 🔄
│   ├── superset.yaml 🔄
│   └── metabase.yaml 🔄
│
├── templates/
│   ├── _helpers.tpl ✅
│   ├── networkpolicies/
│   │   ├── default-deny.yaml ✅
│   │   ├── vault-netpol.yaml ✅
│   │   ├── postgresql-netpol.yaml ✅
│   │   ├── minio-netpol.yaml ✅
│   │   ├── airflow-netpol.yaml ✅
│   │   ├── trino-netpol.yaml 🔄
│   │   ├── keycloak-netpol.yaml 🔄
│   │   ├── openmetadata-netpol.yaml 🔄
│   │   ├── superset-netpol.yaml 🔄
│   │   └── metabase-netpol.yaml 🔄
│   ├── rbac/
│   │   ├── vault-auth-rbac.yaml ✅
│   │   └── airflow-kubernetes-executor-rbac.yaml ✅
│   ├── externalsecrets/
│   │   ├── cluster-secret-store.yaml ✅
│   │   ├── postgresql-secrets.yaml ✅
│   │   ├── minio-secrets.yaml ✅
│   │   ├── airflow-secrets.yaml ✅
│   │   ├── trino-secrets.yaml 🔄
│   │   ├── keycloak-secrets.yaml 🔄
│   │   ├── openmetadata-secrets.yaml 🔄
│   │   ├── superset-secrets.yaml 🔄
│   │   └── metabase-secrets.yaml 🔄
│   └── tests/
│       ├── test-postgresql-connection.yaml ✅
│       ├── test-minio-connection.yaml ✅
│       ├── test-airflow-health.yaml ✅
│       ├── test-trino-connectivity.yaml 🔄
│       └── test-openmetadata-health.yaml 🔄
│
├── docs/
│   ├── vault-setup.md ✅
│   ├── architecture.md 🔄
│   ├── deployment-guide.md 🔄
│   └── adrs/
│       ├── ADR-001-airflow-standalone.md
│       ├── ADR-002-kubernetes-executor.md
│       ├── ADR-003-vault-eso.md
│       ├── ADR-004-superset-metabase.md
│       ├── ADR-005-keycloak-idp.md
│       └── ADR-006-umbrella-anchors.md
│
└── files/
    ├── airflow-dockerfile/
    │   ├── Dockerfile ✅
    │   └── requirements.txt ✅
    ├── keycloak-realm.json 🔄
    └── airflow-connections.json 🔄
```

Legend: ✅ = fertig, 🔄 = in Vorbereitung

---

## Wichtige Meilensteine

| Ticket | Komponente | Status | Datum |
|---|---|---|---|
| 001 | Umbrella Chart Basis | ✅ | 2026-06-21 |
| 004 | Vault + ESO | ✅ | 2026-06-21 |
| 002 | PostgreSQL | ✅ | 2026-06-21 |
| 003 | MinIO | ✅ | 2026-06-21 |
| 005 | Airflow + dbt | ✅ | 2026-06-21 |
| 006 | Trino | 🔄 | - |
| 007 | OpenMetadata | 🔄 | - |
| 008 | Superset | 🔄 | - |
| 009 | Metabase | 🔄 | - |
| 010 | Keycloak | 🔄 | - |
| 011 | Integration Tests | 🔄 | - |
| 012 | Dokumentation | 🔄 | - |

---

## Validierung vor Deployment

Vor dem ersten Deployment sollten folgende Schritte durchgeführt werden:

### 1. Helm Dependency Update
```bash
helm dependency update
```

### 2. Validierungsskript ausführen
```bash
./scripts/validate.sh
```

### 3. Schema generieren (falls noch nicht geschehen)
```bash
./scripts/generate-schema.sh
```

### 4. Vault initialisieren (TICKET-004)
Siehe `docs/vault-setup.md` für:
- vault operator init
- vault operator unseal
- Kubernetes Auth einrichten
- Secrets befüllen

### 5. MinIO Custom Image bauen
```bash
cd files/airflow-dockerfile
docker build -t your-registry/airflow-dbt:3.0.2-python3.12 .
docker push your-registry/airflow-dbt:3.0.2-python3.12
```

### 6. Deployment (wird dokumentiert in TICKET-012)
```bash
helm install data-platform . \
  --namespace data-platform \
  --create-namespace \
  --values values.yaml
```

---

## Bekannte Einschränkungen & TODOs

### TICKET-004 (Vault)
- [ ] Vault Auto Unseal für Production konfigurieren (Cloud KMS)
- [ ] Backup-Strategie für Raft-Snapshots dokumentieren
- [ ] Root Token Rotation Policy definieren

### TICKET-005 (Airflow)
- [ ] Custom Image in Registry pushen (lokal noch nicht gebaut)
- [ ] dbt-profiles ConfigMap erstellen (für dbt Adapter-Config)
- [ ] Ingress-Template für Webserver UI

### TICKET-006+ (verbleibende Komponenten)
- [ ] Keycloak Realm + Clients vorkonfigurieren (TICKET-010)
- [ ] Trino Catalog Config finalisieren (TICKET-006)
- [ ] OpenMetadata Airflow REST-API-Konfiguration (TICKET-007)

---

## Kontakt & Notizen

**Datum dieser Überarbeitung:** 21. Juni 2026
**Nächste geplante Sitzung:** Weiterarbeit an TICKET-006 (Trino)

---

## Zusammenfassung

Mit den abgeschlossenen Tickets 001–005 ist die **Kern-Infrastruktur** für die Data Platform vorhanden:

✅ **Secrets Management:** Vault + ESO als zentrale Verwaltung
✅ **Persistent Storage:** PostgreSQL (Metastore) + MinIO (Object Store)
✅ **Orchestrierung:** Airflow mit KubernetesExecutor + dbt-Integration
✅ **Security:** Durchgängiger Security-Context, NetworkPolicies (Deny-by-Default)
✅ **OIDC/SSO:** Keycloak-Integration geplant (TICKET-010)

Die nächsten Tickets (006–010) erweitern diese Basis um:
- Trino (Distributed SQL Query Engine)
- OpenMetadata (Data Governance)
- Superset + Metabase (BI-Tools)
- Keycloak (Identity Provider)

Integration Tests (TICKET-011) und finale Dokumentation (TICKET-012) folgen danach.
