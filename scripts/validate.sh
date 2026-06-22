#!/bin/bash
# Lokale Validierung des Umbrella-Helm-Charts.
# Kombiniert TICKET-001 (Basis-Lint), TICKET-011 (Security-Checks, helm test)
# und TICKET-016 (Trivy-Scans). Vor jedem Commit ausführen.
set -euo pipefail

echo "=== Data Platform Helm Chart Validation ==="
echo ""

echo "→ Dependency Update..."
helm dependency update 2>&1

echo "→ Lint (strict)..."
helm lint . --values values.yaml --strict

echo "→ Template Rendering..."
helm template data-platform . --values values.yaml > /tmp/rendered.yaml
echo "  Rendered $(wc -l < /tmp/rendered.yaml) Zeilen YAML"

echo "→ Kubernetes Dry-Run..."
kubectl apply --dry-run=client -f /tmp/rendered.yaml

echo "→ Security-Check: Keine Klartext-Secrets in values.yaml/values/..."
if grep -r "password:" values/ values.yaml 2>/dev/null | grep -v "existingSecret\|#\|''\|\"\""; then
  echo "❌ FEHLER: Klartext-Passwort gefunden!"
  exit 1
fi

echo "→ Security-Check: runAsNonRoot überall gesetzt..."
ROOT_CONTAINERS=$(grep -r "runAsNonRoot: false" templates/ 2>/dev/null || true)
if [ -n "$ROOT_CONTAINERS" ]; then
  echo "❌ FEHLER: runAsNonRoot: false gefunden:"
  echo "$ROOT_CONTAINERS"
  exit 1
fi

echo "→ Security-Check: Alle Komponenten-Values-Dateien haben Resource Limits..."
for f in values/*.yaml; do
  [ -e "$f" ] || continue
  if ! grep -q "limits:" "$f"; then
    echo "⚠️  WARNUNG: Keine Resource Limits in $f"
  fi
done

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

echo ""
echo "✓ Alle Validierungen erfolgreich"
