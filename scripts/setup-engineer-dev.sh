#!/bin/bash
set -euo pipefail

echo "=== Data Engineer Dev-Environment Setup ==="
echo "Airflow + Trino + PostgreSQL + MinIO (NO Vault/Keycloak)"
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

# Deploy Data Platform (Engineer Edition)
echo "→ Deploying Airflow + Trino + PostgreSQL + MinIO..."
echo "   (this may take 3-4 minutes)"
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --wait --timeout 10m

echo ""
echo "✓ Data Engineer Dev-Environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Check pod status:"
echo "     kubectl get pods"
echo ""
echo "  2. Access Airflow:"
echo "     kubectl port-forward svc/data-platform-airflow-webserver 8080:8080"
echo "     Then: http://localhost:8080"
echo ""
echo "  3. Access Trino:"
echo "     kubectl port-forward svc/data-platform-trino 8080:8080"
echo "     Then: http://localhost:8080/ui/"
echo ""
echo "  4. Create DAG:"
echo "     kubectl exec -it <airflow-scheduler-pod> -- bash"
echo "     # Place DAGs in /opt/airflow/dags/"
echo ""
echo "For more info, see docs/engineer-dev-setup.md"
