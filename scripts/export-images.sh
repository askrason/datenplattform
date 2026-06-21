#!/bin/bash

set -euo pipefail

# ============================================================
# Export Container Images to TAR Archives
# ============================================================
# Exports all container images from the Helm chart to
# .tar.gz files that can be transferred to air-gapped systems.
#
# Usage:
#   ./scripts/export-images.sh [options]
#
# Options:
#   --output DIR                 Output directory (default: ./images)
#   --values FILE                Override values file (optional)
#   --compress                   Compress tar files to .tar.gz
#   --dry-run                    Show what would be done
#   --help                       Show this help
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default options
OUTPUT_DIR="./images"
VALUES_FILE=""
COMPRESS=false
DRY_RUN=false

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

human_readable_size() {
  local bytes=$1
  if [ "$bytes" -lt 1024 ]; then
    echo "${bytes}B"
  elif [ "$bytes" -lt 1048576 ]; then
    echo "$((bytes / 1024))KB"
  elif [ "$bytes" -lt 1073741824 ]; then
    echo "$((bytes / 1048576))MB"
  else
    echo "$((bytes / 1073741824))GB"
  fi
}

# ============================================================
# Extract Images
# ============================================================

extract_images_from_chart() {
  local values_arg=""

  if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
    values_arg="--values $VALUES_FILE"
  fi

  log_info "Extracting images from Helm chart..."

  cd "$REPO_ROOT"

  helm template data-platform . $values_arg 2>/dev/null \
    | grep -oP '(?<=image:\s*)["\x27]?[\w\-./]+(:\w+)?["\x27]?' \
    | sed 's/["'\'']*//g' \
    | sort -u \
    | grep -v '^$' || true
}

# ============================================================
# Export Images
# ============================================================

export_image_to_tar() {
  local image="$1"
  local output_dir="$2"
  local compress="$3"

  # Sanitize image name for filename
  local filename=$(echo "$image" | sed 's/[/:.]/-/g')
  local tar_file="$output_dir/${filename}.tar"

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would save: $image → $tar_file"
    return 0
  fi

  echo -n "Exporting $image ... "

  if ! docker image inspect "$image" &>/dev/null; then
    echo -e "${YELLOW}not found locally (skipped)${NC}"
    return 0
  fi

  # Save to tar
  if docker save "$image" -o "$tar_file" 2>/dev/null; then
    local size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null)
    local human_size=$(human_readable_size "$size")

    if [ "$compress" = true ]; then
      log_info "Compressing: $tar_file"
      if gzip "$tar_file"; then
        tar_file="${tar_file}.gz"
        size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null)
        human_size=$(human_readable_size "$size")
        echo -e "${GREEN}${human_size}${NC} (compressed)"
      else
        echo -e "${YELLOW}compression failed${NC}"
      fi
    else
      echo -e "${GREEN}${human_size}${NC}"
    fi
  else
    echo -e "${RED}failed${NC}"
    return 1
  fi
}

# ============================================================
# Process All Images
# ============================================================

process_images() {
  local images=("$@")
  local exported_count=0
  local total_size=0
  local failed_count=0

  if [ ${#images[@]} -eq 0 ]; then
    log_error "No images found in chart"
    return 1
  fi

  log_info "Found ${#images[@]} image(s) to export"
  echo ""

  for image in "${images[@]}"; do
    [ -z "$image" ] && continue

    if export_image_to_tar "$image" "$OUTPUT_DIR" "$COMPRESS"; then
      ((exported_count++))
    else
      ((failed_count++))
    fi
  done

  echo ""
  log_info "Export Summary:"
  log_info "  Images found:    ${#images[@]}"
  log_info "  Exported:        $exported_count"
  log_info "  Skipped:         $((${#images[@]} - exported_count - failed_count))"
  log_info "  Failed:          $failed_count"
  log_info "  Output dir:      $OUTPUT_DIR"

  # List exported files
  echo ""
  log_info "Exported files:"
  if [ "$DRY_RUN" = false ] && [ -d "$OUTPUT_DIR" ]; then
    du -sh "$OUTPUT_DIR"/* 2>/dev/null | sed 's/^/  /'
  fi

  if [ $failed_count -gt 0 ]; then
    return 1
  fi

  return 0
}

# ============================================================
# Create Load Script
# ============================================================

create_load_script() {
  local output_dir="$1"

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would create load script"
    return 0
  fi

  local load_script="$output_dir/load-exported-images.sh"

  cat > "$load_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Load exported images into k3s or minikube

TARGET="${1:-k3s}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$TARGET" = "k3s" ]; then
  echo "Loading images into k3s..."
  for tar_file in "$SCRIPT_DIR"/*.tar*; do
    [ -f "$tar_file" ] || continue
    echo "Loading: $tar_file"
    if [[ "$tar_file" == *.gz ]]; then
      gunzip -c "$tar_file" | k3s ctr images import /dev/stdin
    else
      k3s ctr images import "$tar_file"
    fi
  done
elif [ "$TARGET" = "minikube" ]; then
  echo "Loading images into minikube..."
  for tar_file in "$SCRIPT_DIR"/*.tar*; do
    [ -f "$tar_file" ] || continue
    echo "Loading: $tar_file"
    minikube image load "$tar_file"
  done
else
  echo "Usage: $0 [k3s|minikube]"
  exit 1
fi

echo "Done!"
EOF

  chmod +x "$load_script"
  log_success "Created loader script: $load_script"
}

# ============================================================
# Main
# ============================================================

main() {
  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --values)
        VALUES_FILE="$2"
        shift 2
        ;;
      --compress)
        COMPRESS=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
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

  # Check prerequisites
  if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed"
    exit 1
  fi

  if ! command -v helm &>/dev/null; then
    log_error "Helm is not installed"
    exit 1
  fi

  # Create output directory
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$OUTPUT_DIR"
  fi

  # Show configuration
  log_info "Configuration:"
  log_info "  Repository:  $REPO_ROOT"
  log_info "  Output:      $OUTPUT_DIR"
  if [ -n "$VALUES_FILE" ]; then
    log_info "  Values:      $VALUES_FILE"
  fi
  if [ "$COMPRESS" = true ]; then
    log_info "  Compression: enabled (.tar.gz)"
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

  # Create loader script
  create_load_script "$OUTPUT_DIR"

  echo ""
  log_success "Export complete!"
  echo ""
  log_info "To load on target system:"
  if [ "$COMPRESS" = true ]; then
    echo "  1. Transfer images/ directory to target system"
    echo "  2. Run: cd images && ./load-exported-images.sh k3s"
  else
    echo "  1. Transfer *.tar files to target system"
    echo "  2. On target: k3s ctr images import image-name.tar"
  fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
