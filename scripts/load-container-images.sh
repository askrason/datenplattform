#!/bin/bash

set -euo pipefail

# ============================================================
# Load Container Images for Data Platform Helm Chart
# ============================================================
# Extracts all container images from the Helm chart,
# checks which exist locally, downloads missing ones,
# and loads them into k3s/minikube.
#
# Usage:
#   ./scripts/load-container-images.sh [options]
#
# Options:
#   --target k3s|minikube|docker    Default: k3s
#   --values FILE                    Override values file (optional)
#   --dry-run                        Show what would be done
#   --help                           Show this help
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default options
TARGET="k3s"
VALUES_FILE=""
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Helper Functions
# ============================================================

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
  grep "^#" "$0" | grep -v "^#!" | sed 's/^# //' | sed 's/^#//'
}

# ============================================================
# Image Operations
# ============================================================

docker_image_exists_locally() {
  local image="$1"
  docker image inspect "$image" &>/dev/null
}

pull_image() {
  local image="$1"
  log_info "Pulling: $image"
  if docker pull "$image"; then
    log_success "Pulled: $image"
    return 0
  else
    log_error "Failed to pull: $image"
    return 1
  fi
}

load_to_k3s() {
  local image="$1"
  log_info "Loading to k3s: $image"

  # Get image ID for tagging
  local image_id=$(docker image inspect "$image" --format='{{.ID}}' 2>/dev/null | cut -d: -f2 | cut -c1-12)

  if k3s ctr images import /dev/stdin <(docker save "$image" 2>/dev/null); then
    log_success "Loaded to k3s: $image"
    return 0
  else
    log_error "Failed to load to k3s: $image"
    return 1
  fi
}

load_to_minikube() {
  local image="$1"
  log_info "Loading to minikube: $image"

  # Check if minikube is running
  if ! minikube status &>/dev/null; then
    log_error "minikube is not running. Start it with: minikube start"
    return 1
  fi

  if minikube image load "$image"; then
    log_success "Loaded to minikube: $image"
    return 0
  else
    log_error "Failed to load to minikube: $image"
    return 1
  fi
}

# ============================================================
# Extract Images from Helm Chart
# ============================================================

extract_images_from_chart() {
  local values_arg=""

  if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
    values_arg="--values $VALUES_FILE"
  fi

  log_info "Extracting images from Helm chart..."

  cd "$REPO_ROOT"

  # Template the chart and extract all image references
  # This catches: image: foo/bar:tag, spec.image, containers[].image, etc.
  helm template data-platform . $values_arg 2>/dev/null \
    | grep -oP '(?<=image:\s*)["\x27]?[\w\-./]+(:\w+)?["\x27]?' \
    | sed 's/["'\'']*//g' \
    | sort -u \
    | grep -v '^$' || true
}

# ============================================================
# Process Images
# ============================================================

process_images() {
  local images=("$@")
  local pulled_count=0
  local loaded_count=0
  local failed_count=0

  if [ ${#images[@]} -eq 0 ]; then
    log_error "No images found in chart"
    return 1
  fi

  log_info "Found ${#images[@]} image(s) to process"
  echo ""

  for image in "${images[@]}"; do
    # Skip empty lines
    [ -z "$image" ] && continue

    echo -n "Processing $image ... "

    if docker_image_exists_locally "$image"; then
      echo -e "${GREEN}exists locally${NC}"
    else
      echo -e "${YELLOW}not found locally${NC}"

      if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would pull: $image"
        continue
      fi

      if pull_image "$image"; then
        ((pulled_count++))
      else
        ((failed_count++))
        continue
      fi
    fi

    # Load to target runtime
    if [ "$DRY_RUN" = false ]; then
      case "$TARGET" in
        k3s)
          if load_to_k3s "$image"; then
            ((loaded_count++))
          else
            ((failed_count++))
          fi
          ;;
        minikube)
          if load_to_minikube "$image"; then
            ((loaded_count++))
          else
            ((failed_count++))
          fi
          ;;
        docker)
          # Docker target means just ensure images exist
          log_success "Available in Docker: $image"
          ((loaded_count++))
          ;;
      esac
    fi
  done

  echo ""
  log_info "Summary:"
  log_info "  Images found:  ${#images[@]}"
  log_info "  Pulled:        $pulled_count"
  log_info "  Loaded:        $loaded_count"
  log_info "  Failed:        $failed_count"

  if [ $failed_count -gt 0 ]; then
    return 1
  fi

  return 0
}

# ============================================================
# Main
# ============================================================

main() {
  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        TARGET="$2"
        shift 2
        ;;
      --values)
        VALUES_FILE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done

  # Validate target
  case "$TARGET" in
    k3s|minikube|docker)
      ;;
    *)
      log_error "Invalid target: $TARGET (use: k3s, minikube, or docker)"
      exit 1
      ;;
  esac

  # Check prerequisites
  if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed"
    exit 1
  fi

  if ! command -v helm &>/dev/null; then
    log_error "Helm is not installed"
    exit 1
  fi

  if [ "$TARGET" = "k3s" ] && ! command -v k3s &>/dev/null; then
    log_error "k3s is not installed (target=k3s)"
    exit 1
  fi

  if [ "$TARGET" = "minikube" ] && ! command -v minikube &>/dev/null; then
    log_error "minikube is not installed (target=minikube)"
    exit 1
  fi

  # Show configuration
  log_info "Configuration:"
  log_info "  Repository:  $REPO_ROOT"
  log_info "  Target:      $TARGET"
  if [ -n "$VALUES_FILE" ]; then
    log_info "  Values:      $VALUES_FILE"
  fi
  if [ "$DRY_RUN" = true ]; then
    log_info "  Mode:        DRY RUN (no changes)"
  fi
  echo ""

  # Extract and process images
  mapfile -t images < <(extract_images_from_chart)

  if [ ${#images[@]} -eq 0 ]; then
    log_warning "No images extracted from chart (check values?)"
    exit 1
  fi

  process_images "${images[@]}"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
