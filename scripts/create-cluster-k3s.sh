#!/bin/bash

set -euo pipefail

# ============================================================
# Create k3s Cluster for Data Platform
# ============================================================
# Cluster name: data-platform (FIXED)
# Features:
#   - Checks if cluster exists & runs
#   - Installs k3s if needed
#   - Creates data-platform namespace
#   - Validates installation
#
# Usage:
#   ./scripts/create-cluster-k3s.sh
#   ./scripts/create-cluster-k3s.sh --help
#   ./scripts/create-cluster-k3s.sh --lang de
# ============================================================

LANG="${1:-en}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="data-platform"
NAMESPACE="data-platform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Helper Functions
# ============================================================

log_header() {
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "$1"
  echo "════════════════════════════════════════════════════════════"
}

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
Create k3s Cluster for Data Platform

USAGE:
  ./scripts/create-cluster-k3s.sh [OPTIONS]

OPTIONS:
  --help         Show this help
  --lang de      German output (default: English)

CLUSTER:
  Name: data-platform (fixed)
  Namespace: data-platform

FEATURES:
  - Checks if cluster already exists
  - Installs k3s if needed
  - Validates installation
  - Creates data-platform namespace

EXAMPLES:
  # English (default)
  ./scripts/create-cluster-k3s.sh

  # German
  ./scripts/create-cluster-k3s.sh --lang de

NEXT STEPS:
  After successful cluster creation:
  1. Deploy Data Platform:
     ./scripts/setup-k3s-dev.sh

  2. Access the cluster:
     kubectl get pods -n data-platform

  3. Port-forward:
     kubectl port-forward svc/ingress-nginx 80:80 -n ingress-nginx
EOF
}

# ============================================================
# Language Strings
# ============================================================

if [ "$LANG" = "de" ]; then
  MSG_CHECK_PREREQ="Prüfe Voraussetzungen..."
  MSG_KUBECTL_FOUND="kubectl gefunden"
  MSG_KUBECTL_MISSING="kubectl nicht gefunden"
  MSG_K3S_FOUND="k3s gefunden"
  MSG_K3S_MISSING="k3s nicht gefunden, wird installiert"
  MSG_CHECK_CLUSTER="Prüfe ob Cluster existiert..."
  MSG_CLUSTER_RUNNING="Cluster läuft bereits"
  MSG_CLUSTER_NOT_FOUND="Kein Cluster vorhanden, erstelle einen..."
  MSG_INSTALLING_K3S="Installiere k3s..."
  MSG_WAITING_CLUSTER="Warte bis Cluster bereit ist..."
  MSG_CLUSTER_READY="Cluster ist bereit"
  MSG_CREATING_NS="Erstelle Namespace..."
  MSG_NAMESPACE_CREATED="Namespace erstellt"
  MSG_VERIFYING="Überprüfe Installation..."
  MSG_CLUSTER_INFO="Cluster-Informationen:"
  MSG_SUCCESS="k3s Cluster '$CLUSTER_NAME' erfolgreich erstellt!"
  MSG_NEXT_STEPS="Nächste Schritte:"
  MSG_DEPLOY="1. Deploye Data Platform:"
  MSG_ACCESS="2. Zugriff auf Cluster:"
  MSG_PORTFORWARD="3. Port-Forwarding:"
else
  MSG_CHECK_PREREQ="Checking prerequisites..."
  MSG_KUBECTL_FOUND="kubectl found"
  MSG_KUBECTL_MISSING="kubectl not found"
  MSG_K3S_FOUND="k3s found"
  MSG_K3S_MISSING="k3s not found, will be installed"
  MSG_CHECK_CLUSTER="Checking if cluster exists..."
  MSG_CLUSTER_RUNNING="Cluster is already running"
  MSG_CLUSTER_NOT_FOUND="No cluster found, creating one..."
  MSG_INSTALLING_K3S="Installing k3s..."
  MSG_WAITING_CLUSTER="Waiting for cluster to be ready..."
  MSG_CLUSTER_READY="Cluster is ready"
  MSG_CREATING_NS="Creating namespace..."
  MSG_NAMESPACE_CREATED="Namespace created"
  MSG_VERIFYING="Verifying installation..."
  MSG_CLUSTER_INFO="Cluster Info:"
  MSG_SUCCESS="k3s Cluster '$CLUSTER_NAME' created successfully!"
  MSG_NEXT_STEPS="Next steps:"
  MSG_DEPLOY="1. Deploy Data Platform:"
  MSG_ACCESS="2. Access the cluster:"
  MSG_PORTFORWARD="3. Port-forwarding:"
fi

# ============================================================
# Check Prerequisites
# ============================================================

check_prerequisites() {
  log_info "$MSG_CHECK_PREREQ"

  if command -v kubectl &>/dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | cut -d: -f2 | xargs)
    log_success "$MSG_KUBECTL_FOUND: $KUBECTL_VERSION"
  else
    log_error "$MSG_KUBECTL_MISSING"
    log_info "Install from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi

  if command -v k3s &>/dev/null; then
    K3S_VERSION=$(k3s --version 2>/dev/null || echo "unknown")
    log_success "$MSG_K3S_FOUND: $K3S_VERSION"
  else
    log_warning "$MSG_K3S_MISSING"
  fi
}

# ============================================================
# Check if Cluster Exists
# ============================================================

check_cluster_exists() {
  log_info "$MSG_CHECK_CLUSTER"

  # Try to get cluster info
  if kubectl cluster-info &>/dev/null; then
    log_success "$MSG_CLUSTER_RUNNING"

    # Verify we can get nodes
    if kubectl get nodes &>/dev/null; then
      NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
      log_success "Nodes available: $NODES"
      return 0
    fi
  fi

  return 1
}

# ============================================================
# Install k3s
# ============================================================

install_k3s() {
  log_info "$MSG_INSTALLING_K3S"

  if ! command -v curl &>/dev/null; then
    log_error "curl not found. Install curl first."
    exit 1
  fi

  # Download and execute k3s installer
  curl -sfL https://get.k3s.io | sh - 2>&1 | head -20

  if [ $? -eq 0 ]; then
    log_success "k3s installed"
  else
    log_error "k3s installation failed"
    exit 1
  fi
}

# ============================================================
# Wait for Cluster Ready
# ============================================================

wait_for_cluster() {
  log_info "$MSG_WAITING_CLUSTER"

  MAX_ATTEMPTS=30
  ATTEMPT=0

  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    if kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready "; then
      log_success "$MSG_CLUSTER_READY"
      return 0
    fi

    sleep 10
  done

  log_error "Cluster did not become ready within 5 minutes"
  exit 1
}

# ============================================================
# Create Namespace
# ============================================================

create_namespace() {
  log_info "$MSG_CREATING_NS"

  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_warning "Namespace '$NAMESPACE' already exists"
  else
    kubectl create namespace "$NAMESPACE"
    log_success "$MSG_NAMESPACE_CREATED"
  fi

  # Set default context to data-platform namespace
  kubectl config set-context --current --namespace="$NAMESPACE" 2>/dev/null || true
}

# ============================================================
# Verify Installation
# ============================================================

verify_installation() {
  log_info "$MSG_VERIFYING"

  log_header "$MSG_CLUSTER_INFO"

  # Cluster info
  CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
  NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  NAMESPACES=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l)

  echo "  Cluster Name: $CLUSTER_NAME"
  echo "  Context: $CONTEXT"
  echo "  Nodes: $NODES"
  echo "  Namespaces: $NAMESPACES"
  echo "  Default Namespace: $NAMESPACE"
}

# ============================================================
# Main
# ============================================================

main() {
  case "${1:-}" in
    --help|-h)
      show_help
      exit 0
      ;;
    --lang)
      LANG="${2:-en}"
      ;;
  esac

  log_header "k3s Cluster Creation"

  check_prerequisites
  echo ""

  if check_cluster_exists; then
    log_header "Cluster Already Exists"
    verify_installation

    log_header "$MSG_SUCCESS"
    log_info "$MSG_NEXT_STEPS"
    echo "  $MSG_DEPLOY"
    echo "    ./scripts/setup-k3s-dev.sh"
    echo ""
    exit 0
  fi

  install_k3s
  echo ""

  wait_for_cluster
  echo ""

  create_namespace
  echo ""

  verify_installation
  echo ""

  log_header "$MSG_SUCCESS"
  log_info "$MSG_NEXT_STEPS"
  echo "  $MSG_DEPLOY"
  echo "    ./scripts/setup-k3s-dev.sh"
  echo ""
  echo "  $MSG_ACCESS"
  echo "    kubectl get pods -n $NAMESPACE"
  echo ""
  echo "  $MSG_PORTFORWARD"
  echo "    kubectl port-forward svc/ingress-nginx 80:80 -n ingress-nginx"
  echo ""
}

main "$@"
