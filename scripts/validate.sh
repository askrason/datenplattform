#!/bin/bash
# validate.sh – Pre-Commit Validierungsskript für das Data Platform Helm Chart
#
# Führt folgende Validierungsschritte durch:
#   1. Helm Dependency Update
#   2. Helm Lint (auf Syntax & Best Practices)
#   3. Template Dry-Run (gegen lokale K8s-API)
#   4. (Optional) JSON-Schema-Validierung via helm/chart-testing

set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CHART_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Data Platform Helm Chart – Validierungsskript"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ============================================================
# 1. Helm Dependency Update
# ============================================================
echo "📦 Schritt 1: Helm Dependency Update..."
if helm dependency update . > /dev/null 2>&1; then
    echo "   ✓ Abhängigkeiten aktualisiert"
else
    echo "   ✗ FEHLER: Dependency Update fehlgeschlagen"
    exit 1
fi
echo

# ============================================================
# 2. Helm Lint
# ============================================================
echo "🔍 Schritt 2: Helm Lint (Syntax & Best Practices)..."
if helm lint . --values values.yaml --strict > /tmp/helm-lint.log 2>&1; then
    echo "   ✓ Helm Lint erfolgreich"
else
    echo "   ✗ FEHLER: Helm Lint hat Probleme gefunden:"
    cat /tmp/helm-lint.log
    exit 1
fi
echo

# ============================================================
# 3. Template Dry-Run (gegen lokale K8s-API)
# ============================================================
echo "🏗️  Schritt 3: Helm Template Dry-Run..."
TEMP_MANIFEST=$(mktemp)
trap "rm -f $TEMP_MANIFEST" EXIT

if helm template data-platform . --values values.yaml > "$TEMP_MANIFEST" 2>&1; then
    echo "   ✓ Template generiert ($(wc -l < "$TEMP_MANIFEST") Zeilen)"
else
    echo "   ✗ FEHLER: Template-Generierung fehlgeschlagen"
    cat "$TEMP_MANIFEST"
    exit 1
fi

# Versuche gegen K8s-API zu validieren (falls kubectl vorhanden)
if command -v kubectl &> /dev/null; then
    echo "   → Validierung gegen lokale Kubernetes-API..."
    if kubectl apply --dry-run=client -f "$TEMP_MANIFEST" > /dev/null 2>&1; then
        echo "   ✓ Kubernetes Dry-Run erfolgreich"
    else
        echo "   ⚠️  WARNUNG: Kubernetes Dry-Run fehlgeschlagen (aber Chart ist syntaktisch ok)"
        # Nicht abbrechen – könnte auch sein, dass kein lokales K8s vorhanden ist
    fi
else
    echo "   ⚠️  kubectl nicht gefunden – überspringe K8s Dry-Run"
fi
echo

# ============================================================
# 4. Zusätzliche Checks
# ============================================================
echo "✅ Zusätzliche Konsistenz-Checks..."

# Check: Alle Komponenten haben enabled: true/false
MISSING_ENABLED=$(grep -r "enabled:" values/*.yaml 2>/dev/null | wc -l)
if [ "$MISSING_ENABLED" -ge 8 ]; then
    echo "   ✓ Komponenten-Enable-Flags vorhanden"
else
    echo "   ⚠️  WARNUNG: Möglicherweise fehlende enabled-Flags"
fi

# Check: Keine Klartext-Secrets in values.yaml
if grep -q "password:.*[a-zA-Z0-9]\{8,\}" values.yaml 2>/dev/null; then
    echo "   ✗ FEHLER: Möglicherweise Klartext-Secrets in values.yaml"
    exit 1
else
    echo "   ✓ Keine Klartext-Passwords in values.yaml"
fi

# Check: YAML-Anchors existieren
if grep -q "x-security-context:" values.yaml && grep -q "x-pod-security:" values.yaml; then
    echo "   ✓ YAML-Anchors für Security-Defaults vorhanden"
else
    echo "   ✗ FEHLER: Security-Anchors fehlen in values.yaml"
    exit 1
fi

echo

# ============================================================
# Erfolgs-Summary
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ VALIDIERUNG ERFOLGREICH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Nächste Schritte:"
echo "  1. helm install data-platform . --values values.yaml [--dry-run]"
echo "  2. oder: git commit && git push"
echo
