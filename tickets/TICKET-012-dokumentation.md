# TICKET-012: Dokumentation, ADRs & Architektur-Übersicht

## Ziel
Vollständige Projektdokumentation erstellen: Architecture Decision Records (ADRs),
Netzwerk-Dokumentation, Betriebshandbuch und Onboarding-Guide für neue Entwickler.

## Voraussetzungen
- TICKET-001 bis TICKET-011 abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-011
Neue Dateien: docs/architecture.md, docs/networking.md,
  docs/operations.md, docs/onboarding.md,
  docs/adrs/ADR-001 bis ADR-006
```

## Zu erstellende Dateien

### 1. `docs/architecture.md`

Vollständige Architektur-Dokumentation mit:
- Mermaid-Diagramm des gesamten Stacks (alle Komponenten + Verbindungen)
- Schicht-Beschreibung (Storage / Orchestration / Query / Governance / Visualization / Security)
- Komponentenübersicht mit Version, Helm-Chart-Quelle, Namespace
- Skalierungshinweise pro Komponente (welche können horizontal skaliert werden)
- Datenfluss-Beschreibung: Rohdaten → MinIO → dbt/Trino → Superset/Metabase

### 2. `docs/networking.md`

- Vollständige Verbindungsmatrix (aus CLAUDE.md übernehmen + erweitern)
- Mermaid-Netzwerk-Diagramm
- NetworkPolicy-Übersicht: welche Policies schützen welche Ports
- DNS-Konventionen (Service-Namen im Cluster)
- Ingress-Routing-Übersicht (welche URL → welcher Service)

### 3. `docs/operations.md`

Betriebshandbuch:

#### Vault-Betrieb
- Tägliches Unseal-Monitoring (Alerting wenn sealed)
- Secret-Rotation-Prozedur (wie werden Passwörter rotiert ohne Downtime)
- Vault-Backup-Strategie (Raft-Snapshots)

#### PostgreSQL-Betrieb
- Backup-Strategie (pg_dump cronjob oder Velero)
- Replikations-Monitoring
- Datenbank-Größen-Monitoring

#### MinIO-Betrieb
- Bucket-Policy-Management
- Erasure-Coding-Status prüfen
- Speicherkapazitäts-Monitoring

#### Airflow-Betrieb
- DAG-Deployment-Prozess
- Worker-Pod-Monitoring (KubernetesExecutor)
- Log-Rotation (MinIO-basiert)

#### Upgrade-Strategie
- Reihenfolge bei Stack-Upgrades (PostgreSQL zuerst, dann abhängige Services)
- Helm-Upgrade-Befehl mit Backup-Schritt
- Rollback-Prozedur

### 4. `docs/onboarding.md`

Guide für neue Entwickler:

```markdown
## Voraussetzungen (lokal)
- kubectl, helm 3.19+, kind (für lokale Tests)
- Zugriff auf das Container-Registry
- Vault-CLI

## Lokales Entwicklungs-Setup
1. Kind-Cluster starten: `kind create cluster --config ci/kind-config.yaml`
2. Secrets in Vault anlegen: siehe docs/vault-setup.md
3. Chart deployen: `helm install data-platform . --values values.yaml`
4. Tests ausführen: `helm test data-platform`

## Wichtigste Konventionen
- Lies CLAUDE.md bevor du anfängst
- Kein Klartext-Secret in values.yaml → Vault
- Security-Ausnahmen immer kommentieren
- NetworkPolicy vor dem PR testen

## Häufige Fehler
- "ESO kann kein Secret lesen" → Vault nicht initialisiert/unsealed
- "Pod startet nicht" → readOnlyRootFilesystem: true fehlt emptyDir
- "OIDC Login schlägt fehl" → Keycloak Client-Secret nicht in Vault
```

### 5. `docs/adrs/ADR-001-airflow-standalone.md`

Template für alle ADRs:
```markdown
# ADR-001: Airflow eigenständig (nicht als OpenMetadata-Dependency)

## Status
Accepted

## Kontext
OpenMetadata 1.x deployed standardmäßig eine eigene Airflow-Instanz
als Chart-Dependency. Diese Airflow-Instanz ist für allgemeines
Workflow-Management und dbt-Integration ungeeignet, da sie wenig
konfigurierbar ist und kein Custom-Image unterstützt.

## Entscheidung
Airflow wird als eigenständiges Sub-Chart deployed. Das OM-eigene
Airflow wird mit `airflow.enabled: false` deaktiviert.

## Konsequenzen
- ✅ Volle Kontrolle über Airflow-Image (dbt + OM-Ingestion)
- ✅ KubernetesExecutor konfigurierbar
- ✅ Keycloak-OIDC für Airflow möglich
- ⚠️ Manuelle OM-Airflow-Connector-Konfiguration nötig
- ⚠️ OM-Update kann OM-Airflow-Connector-API ändern

## Alternativen verworfen
- OM-eigenes Airflow: zu eingeschränkt, kein Custom-Image
- Airflow als CeleryExecutor: ressourcenintensiver, komplexer
```

Erstelle alle 6 ADR-Dateien (ADR-001 bis ADR-006) nach diesem Template.

## Akzeptanzkriterien

- [ ] `docs/architecture.md` mit Mermaid-Diagramm vorhanden
- [ ] `docs/networking.md` mit vollständiger Verbindungsmatrix
- [ ] `docs/operations.md` mit Betriebsanleitungen für alle Komponenten
- [ ] `docs/onboarding.md` für neue Entwickler
- [ ] `docs/adrs/ADR-001` bis `ADR-006` vollständig
- [ ] `docs/vault-setup.md` (aus TICKET-004) verlinkt
- [ ] `docs/keycloak-setup.md` (aus TICKET-010) verlinkt
- [ ] `docs/metabase-setup.md` (aus TICKET-009) verlinkt
- [ ] Alle Mermaid-Diagramme rendern korrekt (via `mermaid.live` prüfen)
