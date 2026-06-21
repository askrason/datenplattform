# Container Image Management

Pre-loading container images for air-gapped or restricted environments.

---

## The Problem

When deploying on a system with limited internet access (or no internet):
- k3s/minikube can't pull images on-demand
- Deployment fails with `ImagePullBackOff`
- Manual image management is tedious

## The Solution

**`scripts/load-container-images.sh`** automates:
1. Extract all image names from the Helm chart
2. Check which exist locally
3. Pull missing ones
4. Load them into k3s/minikube

---

## Quick Start

### Full-Stack Setup

```bash
# 1. On a machine WITH internet access:
./scripts/load-container-images.sh --target k3s

# OR for minikube:
./scripts/load-container-images.sh --target minikube
```

### See What Would Happen (No Changes)

```bash
./scripts/load-container-images.sh --target k3s --dry-run
```

### Custom Values (Role-Specific)

```bash
# Load images for Engineer Dev only
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-engineer-dev.yaml

# Load images for Analyst Dev
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-analyst-dev.yaml
```

---

## What It Does

### Step 1: Extract Images

```bash
helm template data-platform . | grep image:
```

Finds all container image references in the templated chart. Examples:
```
vault:1.15.0
postgresql:16.2
minio/minio:latest
apache/airflow:2.8.0
# ... and 50+ more
```

### Step 2: Check Local Images

```bash
docker image inspect vault:1.15.0  # exists?
```

**Fast** — uses local Docker daemon only.

### Step 3: Pull Missing Images

```bash
docker pull vault:1.15.0
docker pull postgresql:16.2
# ... all missing images
```

Only pulls what's not already local.

### Step 4: Load into Runtime

**For k3s:**
```bash
docker save vault:1.15.0 | k3s ctr images import /dev/stdin
```

**For minikube:**
```bash
minikube image load vault:1.15.0
```

---

## Typical Workflows

### Scenario 1: Prepare Offline

Machine A (with internet) → Machine B (air-gapped k3s)

```bash
# On Machine A:
./scripts/load-container-images.sh --target k3s

# Verify all images loaded:
k3s ctr images list

# Check: all 60+ images are there
```

### Scenario 2: Role-Specific Load

```bash
# Engineer only needs Airflow + Trino + PostgreSQL + MinIO
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-engineer-dev.yaml

# Analyst only needs Trino + Superset + Metabase + PostgreSQL
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-analyst-dev.yaml
```

### Scenario 3: Incremental Updates

New version of Superset released:

```bash
# Update Chart.yaml → bump superset chart version
# Then:
./scripts/load-container-images.sh --target k3s

# Script pulls ONLY the new version, reuses existing images
```

---

## Output Example

```
ℹ Configuration:
ℹ   Repository:  /home/user/datenplattform
ℹ   Target:      k3s
ℹ   Mode:        normal

ℹ Extracting images from Helm chart...
ℹ Found 62 image(s) to process

Processing vault:1.15.0 ... exists locally
✓ Loaded to k3s: vault:1.15.0

Processing postgresql:16.2 ... not found locally
ℹ Pulling: postgresql:16.2
✓ Pulled: postgresql:16.2
✓ Loaded to k3s: postgresql:16.2

Processing minio/minio:latest ... exists locally
✓ Loaded to k3s: minio/minio:latest

...

ℹ Summary:
ℹ   Images found:  62
ℹ   Pulled:        15
ℹ   Loaded:        62
ℹ   Failed:        0
```

---

## Command Reference

### Basic Usage

```bash
./scripts/load-container-images.sh
# Default: target=k3s, uses base values.yaml
```

### With minikube

```bash
./scripts/load-container-images.sh --target minikube
# Requires: minikube start
```

### Docker Only (No k3s/minikube)

```bash
./scripts/load-container-images.sh --target docker
# Just pulls images, doesn't load to any runtime
```

### Dry Run (Preview)

```bash
./scripts/load-container-images.sh --dry-run
# Shows what would be pulled/loaded WITHOUT making changes
```

### Custom Values

```bash
./scripts/load-container-images.sh \
  --values ci/values-engineer-dev.yaml

# OR multiple overrides:
./scripts/load-container-images.sh \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --values my-custom-overrides.yaml
```

### Combine Options

```bash
# Test run with custom values before actual load
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-analyst-dev.yaml \
  --dry-run
```

---

## Verification

### Check Images in k3s

```bash
# List all loaded images
k3s ctr images list

# Count them
k3s ctr images list | wc -l

# Search for specific image
k3s ctr images list | grep superset
```

### Check Images in minikube

```bash
minikube image ls
```

### Check in Docker

```bash
docker images | head -20
```

---

## Troubleshooting

### "docker pull" fails

```bash
# Check Docker daemon is running
docker ps

# Check Docker can reach registries
docker pull hello-world

# Check internet connectivity
ping docker.io
```

### "k3s ctr" command not found

```bash
# k3s is a single binary, ensure it's in PATH
which k3s

# If not installed:
curl -sfL https://get.k3s.io | sh -
```

### minikube image load fails

```bash
# Check minikube is running
minikube status

# If stopped:
minikube start

# Check minikube has enough disk
minikube df
```

### Image load succeeds, but pod still pulls from registry

K3s might still try to pull if `imagePullPolicy: Always`. Chart uses `IfNotPresent`:

```yaml
# In values.yaml
imagePullPolicy: IfNotPresent  # Use local image if available
```

If you see pulls anyway, check:
```bash
kubectl describe pod <pod-name> | grep "Image:"
```

---

## Performance Notes

**First run:**
- 60+ images ~500MB–2GB download
- Time: 10–30 minutes (depends on internet speed)

**Subsequent runs:**
- Script skips existing images
- Only new/updated images are pulled
- Time: 1–5 minutes

**Network:**
- Pulls from official registries (Docker Hub, Bitnami, etc.)
- Uses standard credentials from `~/.docker/config.json` if needed

---

## Best Practices

### 1. Pre-Load for Deployment Day

```bash
# Do this the day before or morning of deployment
./scripts/load-container-images.sh --target k3s
```

### 2. Use Dry-Run to Validate

```bash
# Always preview first
./scripts/load-container-images.sh --dry-run

# Then run for real
./scripts/load-container-images.sh
```

### 3. Match Values to Deployment

```bash
# If you'll deploy with engineer-dev.yaml, load with it:
./scripts/load-container-images.sh --values ci/values-engineer-dev.yaml
```

### 4. Document Loaded Versions

```bash
# Save a list for your records
k3s ctr images list > loaded-images-$(date +%Y-%m-%d).txt
```

### 5. Automate for CI/CD

```bash
# In your deploy script:
./scripts/load-container-images.sh --target k3s && \
./scripts/switch-to-engineer.sh
```

---

## See Also

- **Deployment Guide**: `docs/k3s-dev-setup.md`
- **Environment Switching**: `docs/environment-switching.md`
- **Operations Manual**: `docs/operations.md`
