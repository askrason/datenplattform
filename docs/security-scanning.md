# Security Scanning with Trivy (TICKET-016)

Automated vulnerability and misconfiguration scanning for the Helm chart and container images.

---

## Overview

Three complementary Trivy scans run automatically in `scripts/validate.sh`:

1. **Config Scan** (`trivy config`) — Helm template misconfiguration detection
2. **Secret Scan** (`trivy fs --scanners secret`) — Embedded secrets in repo
3. **Image Scan** (`trivy image`) — CVE vulnerabilities in container images

---

## Running Locally

### Prerequisites

```bash
# Install Trivy
# macOS:
brew install trivy

# Linux (Ubuntu/Debian):
sudo apt install trivy

# Or download: https://trivy.dev/latest/getting-started/installation/
```

### Run All Validation (including Trivy)

```bash
./scripts/validate.sh
```

**Output:**
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

### Scan Specific Components

```bash
# Just Trivy config scan
trivy config /tmp/rendered.yaml --severity HIGH,CRITICAL

# Just secret scan
trivy fs --scanners secret .

# Scan specific image
trivy image vault:1.15.0 --severity CRITICAL
```

---

## Understanding Findings

### Severity Levels

| Severity | Action | Example |
|----------|--------|---------|
| **CRITICAL** | Block release | RCE, auth bypass, exposed secrets |
| **HIGH** | Fix before merge | Missing securityContext, known CVE |
| **MEDIUM** | Backlog ticket | Information disclosure, weak default |
| **LOW** | Track only | Best-practice improvement |

### Build Behavior

- `validate.sh` exits with code **1** on HIGH or CRITICAL findings
- CI/CD pipeline fails on HIGH/CRITICAL (blocks merge)
- MEDIUM/LOW findings don't block (but should be tracked)

---

## Handling Findings

### Workflow 1: Fix the Issue

```bash
./scripts/validate.sh

# OUTPUT:
# AVD-KSV-0104 – containers[0].securityContext missing runAsNonRoot
# in: values/superset.yaml

# FIX: Add security context
vim values/superset.yaml

# VERIFY:
./scripts/validate.sh  # should pass now
```

### Workflow 2: Document Exception

If the finding is genuinely acceptable (e.g., intentional design choice):

1. **Identify the Check-ID** from Trivy output: `AVD-KSV-0110`
2. **Add to `.trivyignore`** with full justification:

```
# AVD-KSV-0110 – vault (TICKET-004) – IPC_LOCK is required for Vault mlock()
#   and was deliberately allowed as the only additional capability.
#   All other capabilities are dropped (see values/vault.yaml).
#   Review: before each Vault chart major upgrade (2026-12-31).
```

3. **Re-run validation:**

```bash
./scripts/validate.sh  # should pass (exception noted)
```

---

## .trivyignore Format

Each exception must have:

```
<CHECK-ID> – <Component> – <Justification> – <Review Date>
```

**Valid Example:**
```
AVD-KSV-0110 – vault – IPC_LOCK required for mlock() – 2026-12-31
```

**Invalid (too vague):**
```
AVD-KSV-0110 – vault – needed – TODO
```

---

## Custom Image Scanning

If you build a custom Airflow+dbt image (TICKET-005):

```bash
# Scan before pushing
docker build -t your-registry/airflow-dbt:3.0.2-python3.12 .
trivy image your-registry/airflow-dbt:3.0.2-python3.12 --severity CRITICAL

# Or via validate.sh:
AIRFLOW_IMAGE=your-registry/airflow-dbt:3.0.2-python3.12 ./scripts/validate.sh
```

---

## CI/CD Integration

Pipeline has a `security-scan` stage (TICKET-011):

```yaml
security-scan:
  stage: security-scan
  image: aquasec/trivy@sha256:...  # digest-pinned, not latest
  script:
    - helm dependency update
    - helm template data-platform . > /tmp/rendered.yaml
    - trivy config --exit-code 1 --severity HIGH,CRITICAL /tmp/rendered.yaml
    - trivy fs --scanners secret --exit-code 1 .
  allow_failure: false  # blocks merge on findings
```

**Important:** Trivy image is pinned to **digest** (`@sha256:...`), not `latest`, due to March 2026 supply-chain incident.

---

## Supply Chain Security

### Trivy Image Pinning

After the March 2026 supply-chain incident with Trivy distributions:

**❌ DON'T:**
```yaml
image: aquasec/trivy:latest
image: aquasec/trivy:0.50
```

**✅ DO:**
```yaml
image: aquasec/trivy@sha256:abc123def456...
```

### Updates

```bash
# When updating Trivy, pin to new digest
docker pull aquasec/trivy:0.51
docker inspect --format='{{index .RepoDigests 0}}' aquasec/trivy:0.51
# → aquasec/trivy@sha256:newdigest...
```

---

## Common Issues

### "Trivy not installed"

```bash
⚠️  WARNUNG: 'trivy' nicht installiert
```

**Fix:**
```bash
# Install via package manager
brew install trivy  # macOS
sudo apt install trivy  # Ubuntu/Debian

# Or download binary
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
```

### "High/Critical findings in chart"

```bash
AVD-KSV-0104 – Missing securityContext.runAsNonRoot
AVD-KSV-0101 – Privileged pod
```

**First action:** Assume it's a bug in the chart. Fix it:

```bash
# Example: Add security context to Superset
vim values/superset.yaml
# Add: securityContext: { runAsNonRoot: true, ... }

./scripts/validate.sh  # verify
```

### "False positive – need exception"

```bash
# Add to .trivyignore with clear justification
echo "AVD-KSV-0110 – component – reason – 2026-12-31" >> .trivyignore

./scripts/validate.sh  # should pass
```

### "Image scan shows CVEs"

```bash
trivy image vault:1.15.0
# OUTPUT: CVE-2025-12345 – CRITICAL – ...
```

**Actions (in order):**
1. Check if newer version is available: `helm search repo vault`
2. Update Chart.yaml to pin newer version
3. If no newer version, document in `.trivyignore` with CVE link + assessment

---

## Best Practices

### 1. Run Before Every Commit

```bash
./scripts/validate.sh
# Fix any HIGH/CRITICAL findings

git add .
git commit -m "..."
```

### 2. Update Regularly

```bash
# Weekly or monthly, update Trivy rules
trivy config  # pulls latest rules

# Trivy itself
brew upgrade trivy  # or apt upgrade, etc.
```

### 3. Document Exceptions Properly

Don't ignore findings – explain them:

```
✅ AVD-KSV-0110 – vault – IPC_LOCK required for mlock() – 2026-12-31
✗ AVD-KSV-0110 – vault – skip this (vague, unhelpful)
```

### 4. Review Known Issues

Before adding an exception, check CLAUDE.md for known issues:

- **Known Issue #6:** Bitnami OCI migration → older images may lack patches
- **Known Issue #7:** Dev-profile secrets → intentional Klartext for ephemeral dev clusters

---

## See Also

- **Validate Script**: `scripts/validate.sh`
- **Exception List**: `.trivyignore`
- **Known Issues**: CLAUDE.md (Known Issues section)
- **Trivy Docs**: https://trivy.dev
- **Trivy GitHub**: https://github.com/aquasecurity/trivy
