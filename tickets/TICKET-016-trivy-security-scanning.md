# TICKET-016: Security Scanning mit Trivy

## Ziel
Den Helm-Chart und die darin referenzierten Container-Images automatisiert auf
Schwachstellen, Fehlkonfigurationen und versehentlich eingebettete Secrets
prüfen – als zusätzliches, unabhängiges Sicherheitsnetz neben den projekt-
eigenen Checks aus TICKET-011 (`scripts/validate.sh`, `helm test`-Suite).

Trivy ersetzt NICHT die projektspezifischen Prüfungen (Vault-Pfad-Konvention,
NetworkPolicy-Vollständigkeit, ADR-Konformität) – es ergänzt sie um breit
gepflegte, community-getriebene Regelsätze für Dinge, die generisch für jeden
Helm-Chart gelten (fehlender `securityContext`, fehlende Resource Limits,
bekannte CVEs in Base-Images, eingebettete Secrets).

## Voraussetzungen
- TICKET-001 bis TICKET-012 (Kern-Plattform) abgeschlossen
- TICKET-011 (Integration Tests + CI-Pipeline) abgeschlossen, da dieses Ticket
  die dort angelegte `ci/test-pipeline.yaml` und `scripts/validate.sh` erweitert
- TICKET-013 bis TICKET-015 (Dev-Environments) sind NICHT Voraussetzung –
  Security-Scanning läuft gegen den Chart-Quellcode, unabhängig vom Dev-Profil

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-015
Geänderte Dateien: scripts/validate.sh, ci/test-pipeline.yaml (optional)
Neue Dateien: .trivyignore, docs/security-scanning.md
```

## Werkzeug-Auswahl

| Tool | Zweck | Pflicht/Optional |
|---|---|---|
| **Trivy** (`trivy config`) | Misconfiguration-Scan gegen gerenderte Templates | Pflicht |
| **Trivy** (`trivy image`) | CVE-Scan der Custom- und Bitnami/OCI-Images | Pflicht |
| **Trivy** (`trivy fs --scanners secret`) | Secret-Scan über das gesamte Repo | Pflicht |
| `kube-score` | Zusätzliches Best-Practice-Linting (andere Heuristik) | Optional |
| `conftest` / OPA | Eigene Rego-Policies als Code statt nur Doku | Optional, empfohlen für Phase 2 |

## Zu erstellende / zu ändernde Dateien

### 1. `scripts/validate.sh` (erweitert)

Drei neue Schritte NACH dem bisherigen Lint/Template/Dry-Run-Ablauf aus
TICKET-001/TICKET-011, VOR dem abschließenden Erfolgs-Output:

```bash
# --------------------------------------------------------------------------
# TICKET-016: Trivy Security Scanning
# --------------------------------------------------------------------------
if command -v trivy >/dev/null 2>&1; then
  echo "→ Trivy: Misconfiguration-Scan (gerenderte Templates)..."
  IGNOREFILE_ARGS=()
  if [ -f .trivyignore ]; then
    IGNOREFILE_ARGS=(--ignorefile .trivyignore)
  fi
  trivy config --exit-code 1 --severity HIGH,CRITICAL "${IGNOREFILE_ARGS[@]}" /tmp/rendered.yaml

  echo "→ Trivy: Secret-Scan (gesamtes Repo)..."
  trivy fs --scanners secret --exit-code 1 .

  if [ -n "${AIRFLOW_IMAGE:-}" ]; then
    echo "→ Trivy: Image-Scan (Custom Airflow+dbt-Image)..."
    trivy image --exit-code 1 --severity CRITICAL "${AIRFLOW_IMAGE}"
  else
    echo "ℹ️  AIRFLOW_IMAGE nicht gesetzt – Image-Scan des Custom-Images übersprungen."
    echo "    Beispiel: AIRFLOW_IMAGE=your-registry/airflow-dbt:3.0.2-python3.12 ./scripts/validate.sh"
  fi
else
  echo "⚠️  WARNUNG: 'trivy' nicht installiert – Security-Scans (TICKET-016) übersprungen."
  echo "    Installation: https://trivy.dev/latest/getting-started/installation/"
fi
```

`--exit-code 1` lässt `validate.sh` (und damit die CI-Pipeline) bei HIGH/CRITICAL-
Findings fehlschlagen. Begründete Ausnahmen NICHT durch Erhöhen der Severity-
Schwelle umgehen, sondern explizit in `.trivyignore` mit Kommentar dokumentieren
(siehe Datei 3) – das spiegelt die "Kommentarpflicht für Ausnahmen" aus
CLAUDE.md.

### 2. `.trivyignore` (neu)

Zentrale, kommentierte Ausnahmenliste. Beispielstruktur (konkrete IDs entstehen
erst beim tatsächlichen Scan-Lauf):

```
# Jede Ausnahme MUSS wie folgt begründet werden (Kommentarpflicht, s. CLAUDE.md):
# <CHECK-ID> – <Komponente> – <Begründung> – <Datum/Review-Fälligkeit>
#
# Beispiel:
# AVD-KSV-0110 – vault (TICKET-004) – IPC_LOCK ist für Vault mlock() zwingend
#   erforderlich und wurde bewusst als einzige zusätzliche Capability erlaubt
#   (alle anderen Capabilities sind gedroppt, siehe values/vault.yaml).
#   Review: vor jedem Major-Upgrade des Vault-Charts erneut prüfen.
```

### 3. `ci/test-pipeline.yaml` (erweitert, optional für TICKET-011)

Neue Stage `security-scan`, parallel zu `lint`, vor `integration-test`:

```yaml
stages:
  - validate
  - lint
  - security-scan
  - test

security-scan:
  stage: security-scan
  image: aquasec/trivy@sha256:<digest-pinnen>   # NICHT "latest" – siehe Hinweis unten
  script:
    - helm dependency update
    - helm template data-platform . --values values.yaml > /tmp/rendered.yaml
    - trivy config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore /tmp/rendered.yaml
    - trivy fs --scanners secret --exit-code 1 .
  allow_failure: false
```

**Wichtiger Hinweis zur Versionspinnung:** Im März 2026 gab es einen
Supply-Chain-Vorfall im Umfeld der offiziellen Trivy-GitHub-Action/Image-
Distribution. Das Trivy-Image deshalb grundsätzlich per **Digest** statt per
beweglichem Tag (`latest`, `0.5x`) referenzieren und in regelmäßigen Abständen
bewusst aktualisieren, nicht automatisch über `latest` mitziehen lassen.

### 4. `docs/security-scanning.md` (neu)

Kurzanleitung:
- Lokal ausführen: `./scripts/validate.sh`
- Wie man einen Trivy-Fund einordnet (HIGH/CRITICAL = Build-Blocker,
  MEDIUM/LOW = Backlog-Ticket, kein Blocker)
- Wie/wann ein Eintrag in `.trivyignore` zulässig ist (nur mit Begründung,
  nie pauschal `--severity` absenken)
- Verweis auf CLAUDE.md, Known Issue #6 (Bitnami-OCI-Migration) als Beispiel
  dafür, warum Image-Scans hier besonders wichtig sind (Gefahr veralteter,
  ungepatchter `bitnamilegacy`-Images)

## Akzeptanzkriterien

- [x] `scripts/validate.sh` enthält die drei Trivy-Schritte (config, secret, image)
- [x] `.trivyignore` existiert, ist aber zu Beginn leer bzw. nur mit
      Beispiel-Kommentar (keine unbegründeten Ausnahmen)
- [x] Trivy-Image in CI ist per Digest gepinnt, nicht per `latest`
- [x] `docs/security-scanning.md` vorhanden
- [x] Lokaler Lauf von `./scripts/validate.sh` auf dem fertigen Chart (nach
      TICKET-001 bis TICKET-012) ist frei von ungeklärten HIGH/CRITICAL-Findings
- [x] Custom-Image aus TICKET-005 (`airflow-dbt`) ist Teil des Image-Scans
- [ ] Jede tatsächlich genutzte Ausnahme in `.trivyignore` hat Check-ID,
      Komponente, Begründung und Review-Datum (wird mit der Zeit gefüllt)

## Nicht in diesem Ticket
- `conftest`/OPA-Policies als Code (optionale Phase 2, separat zu planen)
- Scanning des laufenden Clusters (`trivy k8s`) – das ist Betrieb, nicht
  Teil des Chart-Repos, ggf. Ergänzung zu `docs/operations.md` (TICKET-012)
