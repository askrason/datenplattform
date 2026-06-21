#!/bin/bash
set -euo pipefail

echo "=== Switching to Full-Stack Dev Environment ==="
echo ""

# Check if data-platform release exists
if ! helm list | grep -q data-platform; then
  echo "ℹ️  First time setup. Installing..."
  helm dependency update >/dev/null 2>&1
else
  echo "ℹ️  Upgrading existing release..."
fi

# Upgrade to Full-Stack Dev (k3s-dev)
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --wait --timeout 15m

echo ""
echo "✓ Switched to Full-Stack Dev Environment"
echo ""
echo "Running pods:"
kubectl get pods --no-headers | grep data-platform || echo "  (waiting for pods to start...)"

echo ""
echo "Next steps:"
echo "  1. Set up port forwarding for Ingress:"
echo "     kubectl port-forward svc/ingress-nginx 80:80 443:443 -n ingress-nginx"
echo ""
echo "  2. Access services via:"
echo "     - Airflow:      http://localhost/airflow/"
echo "     - Superset:     http://localhost/bi/"
echo "     - Metabase:     http://localhost/metabase/"
echo "     - OpenMetadata: http://localhost/catalog/"
echo "     - Keycloak:     http://localhost/auth/"
echo ""
echo "  3. Run tests:"
echo "     helm test data-platform"
echo ""
echo "For more info, see docs/k3s-dev-setup.md"
