#!/bin/bash
set -euo pipefail

echo "=== Data Platform k3s Dev-Environment Setup ==="
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

# Install cert-manager
echo "→ Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update jetstack >/dev/null 2>&1 || true
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout 5m >/dev/null 2>&1 || true
echo "✓ cert-manager installed"

# Install ingress-nginx
echo "→ Installing ingress-nginx..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx >/dev/null 2>&1 || true
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --wait --timeout 5m >/dev/null 2>&1 || true
echo "✓ ingress-nginx installed"

# Update Helm dependencies
echo "→ Updating Helm dependencies..."
helm dependency update >/dev/null 2>&1
echo "✓ Dependencies updated"

# Deploy Data Platform
echo "→ Deploying Data Platform (this may take 5-10 minutes)..."
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --wait --timeout 15m

echo ""
echo "✓ Data Platform k3s Dev-Environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Check pod status:"
echo "     kubectl get pods"
echo ""
echo "  2. Run tests:"
echo "     helm test data-platform"
echo ""
echo "  3. Port forwarding (optional):"
echo "     kubectl port-forward svc/ingress-nginx 80:80 443:443 -n ingress-nginx"
echo ""
echo "  4. Access services (if using port-forwarding):"
echo "     - Airflow:      http://localhost/airflow/"
echo "     - Superset:     http://localhost/bi/"
echo "     - OpenMetadata: http://localhost/catalog/"
echo "     - Keycloak:     http://localhost/auth/"
echo ""
echo "For more info, see docs/k3s-dev-setup.md"
