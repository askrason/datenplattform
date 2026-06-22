# Data Platform Helm Chart – Projektdokumentation

Erstellt: 2026-06-19
Letzte Überarbeitung: 2026-06-19 – TICKET-001-Artefakte vervollständigt (siehe Changelog unten)

## Changelog (diese Überarbeitung)

- `Chart.yaml`: Dependencies `vault`, `external-secrets`, `keycloak`, `metabase`
  ergänzt (waren in den Tickets bereits vorausgesetzt, fehlten aber im Chart).
  Bitnami-Repos auf OCI-Registry umgestellt (s. CLAUDE.md, Known Issue #6).
- `values.yaml`: `global`-Block ergänzt (domain, storageClass, imageRegistry,
  imagePullPolicy, imagePullSecrets, namespaceSuffix). Fehlende
  `CREATE DATABASE keycloak;` ergänzt. Markdown-Link-Artefakt im
  Trino-MinIO-Katalog (`hive.s3.endpoint=[minio](http://minio:9000)`) korrigiert.
  Enabled-Flags für `vault`, `external-secrets`, `keycloak`, `metabase` ergänzt.
- `struktur.txt`: an `CLAUDE.md` angeglichen (`templates/secrets/` →
  `templates/externalsecrets/`, `values/vault.yaml`, `values/keycloak.yaml`,
  `values/external-secrets.yaml` und `templates/tests/` ergänzt).
- `tickets/TICKET-002`, `tickets/TICKET-003`, `tickets/TICKET-005`: Vault-Pfade
  von `secret/data/data-platform/...` auf `secret/data-platform/...`
  korrigiert, damit sie zur in TICKET-004 definierten Secret-Struktur und zur
  dort konfigurierten `ClusterSecretStore` (KV-v2-Pfad ohne `data/`-Segment)
  passen.

## Inhalt

### CLAUDE.md
Projekt-Kontext-Datei für Claude Code. Enthält:
- Stack-Übersicht aller Komponenten
- Architecture Decision Records (ADRs)
- Security Baseline (Non-Negotiable)
- Repository-Struktur
- Coding Conventions
- Verbindungsmatrix
- Known Issues (inkl. Bitnami-Repo-Migration)

### tickets/
16 strukturierte Tickets für Claude Code:

| Ticket | Inhalt |
|--------|--------|
| TICKET-001 | Umbrella Chart Grundstruktur + Security-Anchors |
| TICKET-002 | PostgreSQL Sub-Chart + Hardening |
| TICKET-003 | MinIO Sub-Chart + Hardening |
| TICKET-004 | Vault + External Secrets Operator |
| TICKET-005 | Airflow 3 + dbt-Integration |
| TICKET-006 | Trino Sub-Chart + Kataloge |
| TICKET-007 | OpenMetadata (eigenständig, ohne eigenes Airflow) |
| TICKET-008 | Apache Superset + Keycloak OIDC |
| TICKET-009 | Metabase + oauth2-proxy für SSO |
| TICKET-010 | Keycloak + Realm-Konfiguration |
| TICKET-011 | Integration Tests + helm test Suite |
| TICKET-012 | Dokumentation + ADRs |
| TICKET-013 | k3s Dev-Environment (Full Stack, 8-16 GB RAM) |
| TICKET-014 | Data Engineer Dev-Environment (Airflow+Trino+PG+MinIO, 4-6 GB) |
| TICKET-015 | Data Analyst Dev-Environment (Trino+BI-Tools+PG, 6-8 GB) |
| TICKET-016 | Security Scanning mit Trivy (config/secret/image scans) |

## Empfohlene Reihenfolge

### Kern-Plattform (Production-Ready)
TICKET-001 → TICKET-004 (Vault) → TICKET-002 → TICKET-003
→ TICKET-010 (Keycloak) → TICKET-005 (Airflow) → TICKET-006 (Trino)
→ TICKET-007 (OpenMetadata) → TICKET-008 (Superset) → TICKET-009 (Metabase)
→ TICKET-011 (Tests) → TICKET-012 (Doku)

Vault (TICKET-004) sollte früh deployt werden, da alle anderen
Komponenten ihre Secrets darüber beziehen.

### Optionale Dev-Umgebungen (TICKET-013-016)
Nach Kern-Plattform:
- TICKET-013: k3s Dev-Environment (Full Stack, mit Vault)
- TICKET-014: Data Engineer Dev (Airflow-fokussiert, ohne Vault/Keycloak)
- TICKET-015: Data Analyst Dev (BI-fokussiert, ohne Vault/Keycloak)
- TICKET-016: Trivy Security Scanning (integriert in `./scripts/validate.sh`)

## Verwendung mit Claude Code

1. CLAUDE.md in das Root des Helm-Chart-Repositories legen
2. Pro Session ein Ticket aus `tickets/` als Kontext mitgeben
3. Empfohlen: "Lies CLAUDE.md und setze dann TICKET-00X um"
4. Nach jedem Ticket: `./scripts/validate.sh` ausführen

## Vor dem ersten `helm dependency update`

- Bitnami-Hinweis aus CLAUDE.md ("Known Issues" #6) beachten: Versionen für
  `postgresql` und `keycloak` in `Chart.yaml` ggf. anpassen/pinnen.
- `global.domain`, `global.storageClass` und `global.imageRegistry` in
  `values.yaml` auf die eigene Umgebung anpassen.
- Repository für `metabase` in `Chart.yaml` verifizieren (als TODO markiert).
