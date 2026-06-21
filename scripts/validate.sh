#!/bin/bash
set -euo pipefail

echo "=== Data Platform Helm Chart Validation ==="

echo "→ Dependency Update..."
helm dependency update 2>&1

echo "→ Lint (strict)..."
helm lint . --values values.yaml --strict

echo "→ Template Rendering..."
helm template data-platform . --values values.yaml > /tmp/rendered.yaml
echo "  Rendered $(wc -l < /tmp/rendered.yaml) lines of YAML"

echo "→ Kubernetes Dry-Run..."
kubectl apply --dry-run=client -f /tmp/rendered.yaml

echo "→ Security-Check: No plaintext secrets..."
if grep -r "password:" values/ values.yaml 2>/dev/null | grep -v "existingSecret\|#\|''\|\"\"" | grep -v "password-" || true; then
  echo "⚠️  Check plaintext passwords manually"
fi

echo "→ Security-Check: runAsNonRoot set everywhere..."
if grep -r "runAsNonRoot: false" templates/ 2>/dev/null || true; then
  echo "⚠️  Check runAsNonRoot: false entries manually"
fi

echo "→ Security-Check: Resource limits set..."
for f in values/*.yaml; do
  if ! grep -q "limits:" "$f"; then
    echo "⚠️  WARNING: No resource limits in $f"
  fi
done

echo ""
echo "✓ Validation complete"
