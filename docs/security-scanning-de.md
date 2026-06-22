# Security Scanning mit Trivy (TICKET-016)

Automatisierte Vulnerability und Misconfiguration Scanning für das Helm Chart und Container-Images.

---

## Überblick

Drei komplementäre Trivy-Scans laufen automatisch in `scripts/validate.sh`:

1. **Config Scan** (`trivy config`) — Helm Template Misconfiguration Erkennung
2. **Secret Scan** (`trivy fs --scanners secret`) — Eingebettete Secrets im Repo
3. **Image Scan** (`trivy image`) — CVE-Anfälligkeiten in Container-Images

---

## Lokal ausführen

### Voraussetzungen

```bash
# Installiere Trivy
# macOS:
brew install trivy

# Linux (Ubuntu/Debian):
sudo apt install trivy

# Oder download: https://trivy.dev/latest/getting-started/installation/
```

### Führe alle Validierungen durch (inklusive Trivy)

```bash
./scripts/validate.sh
```

**Ausgabe:**
```
→ Dependency Update...
→ Lint (strict)...
→ Template Rendering...
→ Kubernetes Dry-Run...
→ Security-Check: No plaintext secrets...
→ Security-Check: runAsNonRoot set...
→ Security-Check: Resource limits...
→ Trivy: Misconfiguration-Scan...
→ Trivy: Secret-Scan...
→ Trivy: Image-Scan (Custom Airflow+dbt-Image)...
✓ Alle Validierungen erfolgreich
```

### Scan spezifischer Komponenten

```bash
# Nur Trivy Config Scan
trivy config /tmp/rendered.yaml --severity HIGH,CRITICAL

# Nur Secret Scan
trivy fs --scanners secret .

# Scan spezifisches Image
trivy image vault:1.15.0 --severity CRITICAL
```

---

## Findings verstehen

### Severity-Level

| Severity | Aktion | Beispiel |
|----------|--------|---------|
| **CRITICAL** | Release blockieren | RCE, Auth Bypass, Exposed Secrets |
| **HIGH** | Vor Merge fixen | Missing securityContext, bekannte CVE |
| **MEDIUM** | Backlog Ticket | Information Disclosure, schwache Default |
| **LOW** | Nur tracken | Best-Practice-Verbesserung |

### Build-Verhalten

- `validate.sh` beendet mit Code **1** bei HIGH oder CRITICAL Findings
- CI/CD Pipeline schlägt bei HIGH/CRITICAL fehl (blockiert Merge)
- MEDIUM/LOW Findings blockieren nicht (sollten aber tracked werden)

---

## Findings handhaben

### Workflow 1: Problem beheben

```bash
./scripts/validate.sh

# OUTPUT:
# AVD-KSV-0104 – containers[0].securityContext missing runAsNonRoot
# in: values/superset.yaml

# FIX: Security Context hinzufügen
vim values/superset.yaml

# VERIFY:
./scripts/validate.sh  # sollte jetzt passieren
```

### Workflow 2: Exception dokumentieren

Falls der Finding genuinely akzeptabel ist (z.B. absichtliche Designentscheidung):

1. **Identifiziere Check-ID** aus Trivy Output: `AVD-KSV-0110`
2. **Füge zu `.trivyignore` mit vollständiger Begründung hinzu:**

```
# AVD-KSV-0110 – vault (TICKET-004) – IPC_LOCK ist für Vault mlock() erforderlich
#   und wurde absichtlich als einzige zusätzliche Capability erlaubt.
#   Alle anderen Capabilities werden dropped (siehe values/vault.yaml).
#   Review: vor jedem Vault Chart Major Upgrade (2026-12-31).
```

3. **Führe Validierung neu aus:**

```bash
./scripts/validate.sh  # sollte passieren (Exception notiert)
```

---

## .trivyignore Format

Jede Exception muss haben:

```
<CHECK-ID> – <Component> – <Justification> – <Review Date>
```

**Valides Beispiel:**
```
AVD-KSV-0110 – vault – IPC_LOCK required for mlock() – 2026-12-31
```

**Ungültig (zu vage):**
```
AVD-KSV-0110 – vault – needed – TODO
```

---

## Custom Image Scanning

Falls du ein Custom Airflow+dbt Image baust (TICKET-005):

```bash
# Scanne vor Push
docker build -t your-registry/airflow-dbt:3.0.2-python3.12 .
trivy image your-registry/airflow-dbt:3.0.2-python3.12 --severity CRITICAL

# Oder via validate.sh:
AIRFLOW_IMAGE=your-registry/airflow-dbt:3.0.2-python3.12 ./scripts/validate.sh
```

---

## CI/CD Integration

Pipeline hat ein `security-scan` Stage (TICKET-011):

```yaml
security-scan:
  stage: security-scan
  image: aquasec/trivy@sha256:...  # digest-gepinnt, nicht latest
  script:
    - helm dependency update
    - helm template data-platform . > /tmp/rendered.yaml
    - trivy config --exit-code 1 --severity HIGH,CRITICAL /tmp/rendered.yaml
    - trivy fs --scanners secret --exit-code 1 .
  allow_failure: false  # blockiert Merge bei Findings
```

**Wichtig:** Trivy Image ist **gepinnt** zu **Digest** (`@sha256:...`), nicht `latest`, wegen März 2026 Supply-Chain Incident.

---

## Supply-Chain Sicherheit

### Trivy Image-Pinning

Nach März 2026 Supply-Chain Incident mit Trivy Distributions:

**❌ NICHT:**
```yaml
image: aquasec/trivy:latest
image: aquasec/trivy:0.50
```

**✅ JA:**
```yaml
image: aquasec/trivy@sha256:abc123def456...
```

### Updates

```bash
# Wenn Trivy aktualisierst, pin zu neuem Digest
docker pull aquasec/trivy:0.51
docker inspect --format='{{index .RepoDigests 0}}' aquasec/trivy:0.51
# → aquasec/trivy@sha256:newdigest...
```

---

## Häufige Probleme

### "Trivy nicht installiert"

```bash
⚠️  WARNUNG: 'trivy' nicht installiert
```

**Fix:**
```bash
# Installiere via Package Manager
brew install trivy  # macOS
sudo apt install trivy  # Ubuntu/Debian

# Oder Binary downloaden
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
```

### "High/Critical Findings im Chart"

```bash
AVD-KSV-0104 – Missing securityContext.runAsNonRoot
AVD-KSV-0101 – Privileged pod
```

**Erste Aktion:** Nehme an, es ist ein Bug im Chart. Fixe es:

```bash
# Beispiel: Security Context zu Superset hinzufügen
vim values/superset.yaml
# Füge hinzu: securityContext: { runAsNonRoot: true, ... }

./scripts/validate.sh  # Verifiziere
```

### "False Positive – Exception brauchbar"

```bash
# Füge zu .trivyignore mit klarer Begründung hinzu
echo "AVD-KSV-0110 – component – reason – 2026-12-31" >> .trivyignore

./scripts/validate.sh  # sollte passieren
```

### "Image Scan zeigt CVEs"

```bash
trivy image vault:1.15.0
# OUTPUT: CVE-2025-12345 – CRITICAL – ...
```

**Maßnahmen (in Reihenfolge):**
1. Überprüfe, ob neuere Version verfügbar ist: `helm search repo vault`
2. Update Chart.yaml zu neuere Version pinnen
3. Falls keine neuere Version, dokumentiere in `.trivyignore` mit CVE Link + Assessment

---

## Best Practices

### 1. Vor jedem Commit ausführen

```bash
./scripts/validate.sh
# Fixe beliebige HIGH/CRITICAL Findings

git add .
git commit -m "..."
```

### 2. Regelmäßig aktualisieren

```bash
# Wöchentlich oder monatlich, update Trivy Rules
trivy config  # pullt neueste Rules

# Trivy selbst
brew upgrade trivy  # oder apt upgrade, etc.
```

### 3. Exceptions richtig dokumentieren

Ignoriere Findings nicht — erkläre sie:

```
✅ AVD-KSV-0110 – vault – IPC_LOCK required for mlock() – 2026-12-31
✗ AVD-KSV-0110 – vault – skip this (vage, unhelpreich)
```

### 4. Known Issues überprüfen

Vor Exception hinzufügen, überprüfe CLAUDE.md für Known Issues:

- **Known Issue #6:** Bitnami OCI Migration → ältere Images könnten Patches fehlen
- **Known Issue #7:** Dev-Profile Secrets → absichtlich Klartext für ephemerale Dev-Cluster

---

## Siehe auch

- **Validate Script**: `scripts/validate.sh`
- **Exception List**: `.trivyignore`
- **Known Issues**: CLAUDE.md (Known Issues Sektion)
- **Trivy Docs**: https://trivy.dev
- **Trivy GitHub**: https://github.com/aquasecurity/trivy
