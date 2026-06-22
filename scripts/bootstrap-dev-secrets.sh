#!/bin/bash

set -euo pipefail

# ============================================================
# Bootstrap Development Secrets (TICKET-014, TICKET-015)
# ============================================================
# Creates Kubernetes Secrets for dev-only environments
# where Vault + External Secrets Operator are disabled.
#
# IMPORTANT: This is ONLY for local development clusters.
# NEVER use in shared or production environments.
#
# Usage:
#   ./scripts/bootstrap-dev-secrets.sh engineer
#   ./scripts/bootstrap-dev-secrets.sh analyst
#   ./scripts/bootstrap-dev-secrets.sh --help
# ============================================================

PROFILE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

show_help() {
  cat << 'EOF'
Bootstrap Development Secrets (TICKET-014, TICKET-015)

Creates temporary Kubernetes Secrets for local development where
Vault + External Secrets Operator are disabled.

USAGE:
  ./scripts/bootstrap-dev-secrets.sh engineer
  ./scripts/bootstrap-dev-secrets.sh analyst

PROFILES:
  engineer    Creates secrets for engineer-dev.yaml profile
              (Airflow, Trino, PostgreSQL, MinIO)

  analyst     Creates secrets for analyst-dev.yaml profile
              (Trino, Superset, Metabase, PostgreSQL)

IMPORTANT:
  - For LOCAL development only (ephemeral k3s clusters)
  - Secrets are generated randomly and NOT committed to git
  - Use different values for shared/production environments
  - Delete secrets when tearing down the cluster

EXAMPLES:
  # Setup engineer environment with secrets
  ./scripts/bootstrap-dev-secrets.sh engineer
  helm install data-platform . \
    --values values.yaml \
    --values ci/values-engineer-dev.yaml

  # Setup analyst environment with secrets
  ./scripts/bootstrap-dev-secrets.sh analyst
  helm install data-platform . \
    --values values.yaml \
    --values ci/values-analyst-dev.yaml

See also: docs/engineer-dev-setup.md, docs/analyst-dev-setup.md
EOF
}

# Generate random password
generate_password() {
  local length=${1:-32}
  openssl rand -base64 "$length" 2>/dev/null | tr -d '\n' || \
  head -c "$length" /dev/urandom | base64 | tr -d '\n'
}

# Create a kubernetes secret from key=value pairs
create_secret() {
  local secret_name="$1"
  shift
  local args=()

  # Build literal arguments
  for pair in "$@"; do
    args+=(--from-literal="$pair")
  done

  log_info "Creating secret: $secret_name"
  if kubectl create secret generic "$secret_name" "${args[@]}" 2>/dev/null; then
    log_success "Created: $secret_name"
  else
    # Secret might already exist
    log_warning "Secret $secret_name already exists (skipping)"
  fi
}

# Bootstrap Engineer Profile Secrets
bootstrap_engineer() {
  log_info "Bootstrapping Engineer Dev Profile Secrets..."
  echo ""

  # PostgreSQL credentials
  local pg_pass=$(generate_password)
  create_secret "data-platform-postgresql-credentials" \
    "username=postgres" \
    "password=$pg_pass"

  # Airflow DB credentials
  local airflow_db_pass=$(generate_password)
  create_secret "data-platform-airflow-db-credentials" \
    "username=airflow" \
    "password=$airflow_db_pass"

  # Airflow OIDC (stub - no Keycloak in dev)
  create_secret "data-platform-airflow-oidc-credentials" \
    "client_id=airflow-dev" \
    "client_secret=dev-stub-secret-no-keycloak"

  # MinIO credentials
  local minio_key=$(generate_password 20)
  local minio_secret=$(generate_password 32)
  create_secret "data-platform-minio-credentials" \
    "rootUser=minioadmin" \
    "rootPassword=$minio_key"

  # Trino credentials
  local trino_pass=$(generate_password)
  create_secret "data-platform-trino-credentials" \
    "username=admin" \
    "password=$trino_pass"

  echo ""
  log_success "Engineer profile secrets created"
  echo ""
  log_info "Next steps:"
  echo "  helm install data-platform . \\"
  echo "    --values values.yaml \\"
  echo "    --values ci/values-engineer-dev.yaml"
  echo ""
  log_warning "REMINDER: These secrets are for LOCAL DEV ONLY"
}

# Bootstrap Analyst Profile Secrets
bootstrap_analyst() {
  log_info "Bootstrapping Analyst Dev Profile Secrets..."
  echo ""

  # PostgreSQL credentials
  local pg_pass=$(generate_password)
  create_secret "data-platform-postgresql-credentials" \
    "username=postgres" \
    "password=$pg_pass"

  # Trino credentials
  local trino_pass=$(generate_password)
  create_secret "data-platform-trino-credentials" \
    "username=admin" \
    "password=$trino_pass"

  # Superset DB credentials
  local superset_db_pass=$(generate_password)
  create_secret "data-platform-superset-db-credentials" \
    "username=superset" \
    "password=$superset_db_pass"

  # Metabase DB credentials
  local metabase_db_pass=$(generate_password)
  create_secret "data-platform-metabase-db-credentials" \
    "username=metabase" \
    "password=$metabase_db_pass"

  echo ""
  log_success "Analyst profile secrets created"
  echo ""
  log_info "Next steps:"
  echo "  helm install data-platform . \\"
  echo "    --values values.yaml \\"
  echo "    --values ci/values-analyst-dev.yaml"
  echo ""
  log_warning "REMINDER: These secrets are for LOCAL DEV ONLY"
}

# Verify kubectl is available
if ! command -v kubectl &>/dev/null; then
  log_error "kubectl not found. Install it and configure kubeconfig."
  exit 1
fi

# Check if connected to a cluster
if ! kubectl cluster-info &>/dev/null; then
  log_error "Not connected to a Kubernetes cluster."
  log_info "Start your cluster and configure kubectl:"
  echo "  k3s # or minikube start, kind create cluster, etc."
  exit 1
fi

# Main
case "${PROFILE}" in
  engineer)
    bootstrap_engineer
    ;;
  analyst)
    bootstrap_analyst
    ;;
  --help|-h)
    show_help
    exit 0
    ;;
  "")
    log_error "Profile required (engineer or analyst)"
    show_help
    exit 1
    ;;
  *)
    log_error "Unknown profile: $PROFILE"
    show_help
    exit 1
    ;;
esac
