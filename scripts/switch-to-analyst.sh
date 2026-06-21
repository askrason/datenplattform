#!/bin/bash
set -euo pipefail

echo "=== Switching to Analyst Dev Environment ==="
echo ""

# Check if data-platform release exists
if ! helm list | grep -q data-platform; then
  echo "ℹ️  First time setup. Installing..."
  helm dependency update >/dev/null 2>&1
else
  echo "ℹ️  Upgrading existing release..."
fi

# Upgrade to Analyst Dev
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-analyst-dev.yaml \
  --wait --timeout 10m

echo ""
echo "✓ Switched to Analyst Dev Environment"
echo ""
echo "Running pods:"
kubectl get pods --no-headers | grep data-platform || echo "  (waiting for pods to start...)"

echo ""
echo "Next steps:"
echo "  1. Access Trino:"
echo "     kubectl port-forward svc/data-platform-trino 8080:8080"
echo "     → http://localhost:8080/ui/"
echo ""
echo "  2. Access Superset:"
echo "     kubectl port-forward svc/data-platform-superset 8088:8088"
echo "     → http://localhost:8088 (admin/admin)"
echo ""
echo "  3. Access Metabase:"
echo "     kubectl port-forward svc/data-platform-metabase 3000:3000"
echo "     → http://localhost:3000"
