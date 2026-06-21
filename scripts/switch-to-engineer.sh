#!/bin/bash
set -euo pipefail

echo "=== Switching to Engineer Dev Environment ==="
echo ""

# Check if data-platform release exists
if ! helm list | grep -q data-platform; then
  echo "ℹ️  First time setup. Installing..."
  helm dependency update >/dev/null 2>&1
else
  echo "ℹ️  Upgrading existing release..."
fi

# Upgrade to Engineer Dev
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --wait --timeout 10m

echo ""
echo "✓ Switched to Engineer Dev Environment"
echo ""
echo "Running pods:"
kubectl get pods --no-headers | grep data-platform || echo "  (waiting for pods to start...)"

echo ""
echo "Next steps:"
echo "  1. Access Airflow:"
echo "     kubectl port-forward svc/data-platform-airflow-webserver 8080:8080"
echo ""
echo "  2. Access Trino:"
echo "     kubectl port-forward svc/data-platform-trino 8080:8080"
echo ""
echo "  3. Check data in MinIO:"
echo "     kubectl port-forward svc/data-platform-minio 9001:9001"
