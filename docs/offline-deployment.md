# Offline & Air-Gapped Deployment Guide

Strategies for deploying the Data Platform in environments with limited or no internet access.

---

## Overview

Three approaches, from simplest to most robust:

| Approach | Use Case | Complexity | Network Required |
|----------|----------|-----------|------------------|
| **Online Load** | k3s has internet | Simple | Yes (once) |
| **Image Export** | Transfer via USB/NFS | Medium | No (after export) |
| **Registry Mirror** | Multi-system deployments | Complex | No (after setup) |

---

## Approach 1: Online Load (Simplest)

Requires internet access on the k3s/minikube host, but only once.

### Steps

```bash
# 1. On the k3s host with internet:
cd /path/to/datenplattform
./scripts/load-container-images.sh --target k3s

# 2. Verify all images loaded:
k3s ctr images list | wc -l
# Should show ~60+ images

# 3. Now deploy:
./scripts/switch-to-engineer.sh
```

**Time:** 10–30 minutes (depending on bandwidth)
**Complexity:** Low
**Prerequisites:** Docker + k3s + internet

---

## Approach 2: Export & Transfer (Medium)

Pre-load images on a system with internet, export to TAR archives, transfer to air-gapped system.

### 2A: Export on Connected System

```bash
# On Machine A (with internet):
./scripts/export-images.sh --output ./images --compress

# This creates:
# images/vault-1.15.0.tar.gz
# images/postgresql-16.2.tar.gz
# images/minio-minio-latest.tar.gz
# ... (~30+ compressed archives)
# images/load-exported-images.sh
```

**Size:** ~500MB–2GB depending on compression

### 2B: Transfer Archives

```bash
# Via USB stick, SCP, or network share:
scp -r images/ user@airgapped-system:/tmp/

# Or:
rsync -av images/ user@airgapped-system:/tmp/
```

### 2C: Load on Air-Gapped System

```bash
# On Machine B (no internet):
cd /tmp/images
./load-exported-images.sh k3s

# Verify:
k3s ctr images list | wc -l
```

**Time:** 
- Export: 15–20 minutes
- Transfer: depends on network/USB speed
- Load: 5–10 minutes
- **Total (offline part):** ~20 minutes

**Complexity:** Medium

---

## Approach 3: Private Registry Mirror (Advanced)

For multiple k3s clusters or regular updates. Requires a private Docker registry.

### 3A: Set Up Registry

```bash
# On an internal machine with internet access:

# Option A: Docker Registry (simplest)
docker run -d \
  -p 5000:5000 \
  --name registry \
  registry:2

# Option B: Harbor (more features)
docker-compose up -d  # (via harbor docker-compose.yml)
```

### 3B: Sync Images to Registry

```bash
# Create sync script (or use skopeo/registry-sync)
./scripts/export-images.sh --output ./images

# Retag all images to your registry:
for image in $(docker images --format "{{.Repository}}:{{.Tag}}"); do
  docker tag "$image" "registry.internal:5000/$image"
  docker push "registry.internal:5000/$image"
done
```

### 3C: Update Helm Values

```yaml
# ci/values-offline.yaml
global:
  imageRegistry: "registry.internal:5000"
```

### 3D: Deploy from Registry

```bash
helm install data-platform . \
  --values values.yaml \
  --values ci/values-offline.yaml
```

**Complexity:** High
**Benefit:** Seamless updates, multiple clusters, versioning

---

## Recommended: Hybrid Approach

For most organizations:

```
1. Use Approach 1 (Online Load) for initial deployment
   → k3s host downloads images once
   → Fast, simple, low overhead

2. If scaling to multiple systems:
   → Switch to Approach 2 (Export & Transfer)
   → Pre-export once, reuse across deployments
   → Document process in ops runbook

3. For production with frequent updates:
   → Implement Approach 3 (Private Registry)
   → Justifies infrastructure investment for large deployments
```

---

## Quick Reference Scripts

### Load Online

```bash
./scripts/load-container-images.sh --target k3s
```

### Export All Images

```bash
./scripts/export-images.sh --output ./images --compress
```

### Export Subset (Engineer Dev Only)

```bash
./scripts/export-images.sh \
  --output ./images-engineer \
  --values ci/values-engineer-dev.yaml \
  --compress
```

### Dry-Run (Preview)

```bash
./scripts/export-images.sh --output ./images --dry-run
```

### List Loaded Images

```bash
k3s ctr images list
```

---

## Networking Topology

### Online Load
```
┌─────────────────┐
│   k3s Host      │
│                 │
│ ┌─────────────┐ │
│ │   Docker    │ │──→ Docker Hub / Registries
│ │   daemon    │ │    (pull images)
│ └─────────────┘ │
│                 │
│ ┌─────────────┐ │
│ │   k3s       │ │
│ │   cluster   │ │
│ └─────────────┘ │
└─────────────────┘
```

### Export & Transfer
```
┌──────────────┐           ┌──────────────────────┐
│ Machine A    │           │ Machine B (Offline)  │
│ (Internet)   │           │                      │
│              │──USB──→   │ ┌──────────────────┐ │
│ ┌──────────┐ │   stick   │ │      k3s         │ │
│ │ Docker   │ │ or SCP    │ │      cluster     │ │
│ └──────────┘ │           │ └──────────────────┘ │
│              │           │                      │
│ Export .tar  │           │ Load .tar files      │
│ files        │           │                      │
└──────────────┘           └──────────────────────┘
```

### Private Registry
```
┌────────────────────────────────────────────────────┐
│ Internal Network                                   │
│                                                    │
│  ┌──────────────┐      ┌──────────────────────┐  │
│  │ Registry     │◄─────│ Machine A (Sync)     │  │
│  │ (internal)   │      │ - pulls from Docker  │  │
│  │              │      │ - pushes to registry │  │
│  └──────────────┘      └──────────────────────┘  │
│         ▲                                          │
│         │                                          │
│         │ (pull)                                   │
│         │                                          │
│  ┌──────────────┐      ┌──────────────────────┐  │
│  │ k3s Cluster1 │      │ k3s Cluster2         │  │
│  │              │      │                      │  │
│  └──────────────┘      └──────────────────────┘  │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### Export Fails: "docker: command not found"

```bash
# Ensure Docker is running
docker ps

# If not installed:
# macOS: brew install docker
# Linux: sudo apt-get install docker.io
# Windows: Install Docker Desktop
```

### Load Fails: "k3s: command not found"

```bash
# k3s must be installed
which k3s

# If not:
curl -sfL https://get.k3s.io | sh -
```

### TAR Files Are Very Large

```bash
# Use compression (recommended)
./scripts/export-images.sh --compress

# Or manually:
tar czf images.tar.gz images/
```

### Transfer Slow with SCP

```bash
# Compress the directory first
tar czf images.tar.gz images/

# Then transfer (much faster)
scp images.tar.gz user@target:/tmp/

# On target:
tar xzf /tmp/images.tar.gz
cd images && ./load-exported-images.sh k3s
```

### Some Images Not Found Locally

```bash
# Dry-run to see what would be pulled
./scripts/export-images.sh --dry-run

# This is normal — export only exports what exists.
# Use load-container-images.sh first to pull them:
./scripts/load-container-images.sh --target k3s --dry-run
./scripts/load-container-images.sh --target k3s  # pull images

# Then export
./scripts/export-images.sh --compress
```

---

## Security Considerations

### Image Integrity

**Risk:** Tampered images in transit

**Mitigation:**
```bash
# Save image digests before export
k3s ctr images list | grep sha256 > image-digests.txt

# On target, verify digests match:
k3s ctr images list | grep sha256
```

### Private Registry Authentication

**Risk:** Unauthorized access to internal registry

**Mitigation:**
```bash
# Use basic auth or TLS
docker run -d \
  -p 5000:5000 \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -v /etc/registry/htpasswd:/auth/htpasswd:ro \
  registry:2
```

### Network Isolation

**Risk:** Images from compromised networks

**Best Practice:**
```bash
# Only transfer images between networks you control
# Verify source and destination
sha256sum images.tar.gz  # note checksum
# transfer
sha256sum images.tar.gz  # verify matches
```

---

## See Also

- **Image Loading**: `docs/image-management.md`
- **k3s Setup**: `docs/k3s-dev-setup.md`
- **Environment Switching**: `docs/environment-switching.md`
- **Operations Manual**: `docs/operations.md`
