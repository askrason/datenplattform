#!/bin/bash
set -euo pipefail

echo "=== Data Analyst Dev-Environment Setup ==="
echo "Trino + Superset + Metabase + PostgreSQL (NO Vault/Keycloak/Airflow)"
echo ""

# Check prerequisites
echo "→ Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found. Please install kubectl."
  exit 1
fi

if ! command -v helm &> /dev/null; then
  echo "❌ helm not found. Please install helm."
  exit 1
fi

echo "✓ kubectl and helm found"
echo ""

# Update Helm dependencies
echo "→ Updating Helm dependencies..."
helm dependency update >/dev/null 2>&1
echo "✓ Dependencies updated"

# Deploy Data Platform (Analyst Edition)
echo "→ Deploying Trino + Superset + Metabase + PostgreSQL..."
echo "   (this may take 4-5 minutes)"
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-analyst-dev.yaml \
  --wait --timeout 10m

echo ""
echo "✓ Data Analyst Dev-Environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Check pod status:"
echo "     kubectl get pods"
echo ""
echo "  2. Access Trino:"
echo "     kubectl port-forward svc/data-platform-trino 8080:8080"
echo "     Then: http://localhost:8080/ui/"
echo ""
echo "  3. Access Superset:"
echo "     kubectl port-forward svc/data-platform-superset 8088:8088"
echo "     Then: http://localhost:8088"
echo ""
echo "  4. Access Metabase:"
echo "     kubectl port-forward svc/data-platform-metabase 3000:3000"
echo "     Then: http://localhost:3000"
echo ""
echo "For more info, see docs/analyst-dev-setup.md"
