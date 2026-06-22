# TICKET-013: k3s Dev-Environment Setup für WSL2

## Ziel
Entwickler können auf WSL2 + k3s eine lokale Data-Platform-Umgebung in unter 5 Minuten deployen.
Reduzierte Ressourcen-Anforderungen (8 GB RAM statt 20 GB Production).
Einfache one-liner Setup mit Validierung.

## Voraussetzungen
- TICKET-001 bis TICKET-012 abgeschlossen
- WSL2 mit ca. 8-16 GB RAM
- kubectl und helm installiert

## Hinweis (diese Überarbeitung - TICKET-013 Vault-Fix)
Dieses Profil lässt Vault + External Secrets Operator AKTIV (nur mit reduzierten
Replicas) – im Gegensatz zu TICKET-014/TICKET-015, die beide komplett ohne
Vault/Keycloak laufen und dafür einen eigenen Secret-Bootstrap-Mechanismus
benötigen (siehe dort). Hier reicht es, Vault in den Standalone-Modus zu
versetzen.

**WICHTIG:** `server.replicaCount` existiert im offiziellen HashiCorp Vault Chart
NICHT. Verwende stattdessen `ha.enabled: false + standalone.enabled: true`.

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-012
Neue Dateien: ci/values-k3s-dev.yaml, scripts/setup-k3s-dev.sh, docs/k3s-dev-setup.md
Überarbeitung: Vault-Konfiguration korrigiert (ha.enabled + standalone.enabled)
```

## Zu erstellende Dateien

### 1. `ci/values-k3s-dev.yaml`

Override-Datei für k3s Dev-Umgebung. Nur Änderungen zu Production-Defaults:

```yaml
# k3s Dev-Umgebung: Reduzierte Replicas und Ressourcen

# Storage: k3s local-path provisioner
global:
  storageClass: "local-path"

# PostgreSQL: Single Primary (kein Replica in Dev)
postgresql:
  primary:
    replicaCount: 1
  readReplicas:
    enabled: false
  persistence:
    size: 20Gi  # Reduziert

# Vault: Standalone-Modus statt HA (kein Cluster im Dev)
# WICHTIG: server.replicaCount existiert nicht im offiziellen Chart.
# Verwende stattdessen ha.enabled + standalone.enabled
vault:
  server:
    ha:
      enabled: false
    standalone:
      enabled: true
      config: |
        ui = true
        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
        }
        storage "file" {
          path = "/vault/data"
        }
    dataStorage:
      size: 10Gi

# Keycloak: Single Replica
keycloak:
  replicaCount: 1
  cache:
    enabled: false  # Keine Infinispan-Clustering nötig

# MinIO: Single Node (statt 4 Nodes)
minio:
  mode: standalone
  replicas: 1
  persistence:
    size: 100Gi

# Airflow: Reduced Resources
airflow:
  scheduler:
    resources:
      requests: { cpu: 250m, memory: 512Mi }
      limits: { cpu: 500m, memory: 1Gi }

# Superset: Single Replica
superset:
  replicaCount: 1
  celeryWorker:
    replicaCount: 1
  redis:
    master:
      resources:
        requests: { cpu: 50m, memory: 128Mi }
        limits: { cpu: 100m, memory: 256Mi }

# Trino: Single Coordinator, 1 Worker
trino:
  server:
    workers: 1
  coordinator:
    resources:
      requests: { cpu: 500m, memory: 1Gi }
      limits: { cpu: 1000m, memory: 2Gi }

# OpenMetadata: Single Replica
openmetadata:
  replicaCount: 1

# Metabase: Single Replica
metabase:
  replicaCount: 1
```

### 2. `scripts/setup-k3s-dev.sh`

Bash-Script für komplettes Setup:

```bash
#!/bin/bash
set -euo pipefail

echo "=== Data Platform k3s Dev-Environment Setup ==="
echo ""

# 1. Check Prerequisites
echo "→ Checking prerequisites..."
command -v k3s >/dev/null || {
  echo "Installing k3s..."
  curl -sfL https://get.k3s.io | sh -
}

command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }
command -v helm >/dev/null || { echo "helm not found"; exit 1; }

# 2. Install cert-manager
echo "→ Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update jetstack >/dev/null 2>&1 || true
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout 5m >/dev/null 2>&1 || true

# 3. Install ingress-nginx
echo "→ Installing ingress-nginx..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx >/dev/null 2>&1 || true
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --wait --timeout 5m >/dev/null 2>&1 || true

# 4. Update Helm dependencies
echo "→ Updating Helm dependencies..."
helm dependency update >/dev/null 2>&1

# 5. Deploy Data Platform
echo "→ Deploying Data Platform (this may take 5-10 minutes)..."
helm upgrade --install data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --wait --timeout 15m

echo ""
echo "✓ Data Platform k3s Dev-Environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Port forwarding (optional):"
echo "     kubectl port-forward svc/ingress-nginx 80:80 443:443 -n ingress-nginx"
echo ""
echo "  2. Access services:"
echo "     - Airflow:      http://localhost/airflow/"
echo "     - Superset:     http://localhost/bi/"
echo "     - OpenMetadata: http://localhost/catalog/"
echo "     - Keycloak:     http://localhost/auth/"
echo ""
echo "  3. Run tests:"
echo "     helm test data-platform"
echo ""
echo "  4. Check pod status:"
echo "     kubectl get pods"
```

### 3. `docs/k3s-dev-setup.md`

Dokumentation für Entwickler:

```markdown
# k3s Dev-Environment Setup (WSL2)

## Prerequisites

- WSL2 with 8-16 GB RAM
- kubectl and helm installed locally
- Git repository cloned

## Quick Start

```bash
cd datenplattform
chmod +x scripts/setup-k3s-dev.sh
./scripts/setup-k3s-dev.sh
```

That's it! Environment will be ready in 5-10 minutes.

## Configuration

Dev-Umgebung nutzt reduzierte Ressourcen:
- PostgreSQL: Single Primary (kein Replica)
- Vault: Single Replica
- Keycloak: Single Replica
- MinIO: Standalone Mode (1 Node)
- Airflow: Minimal Resources (CPU/Memory Limits reduziert)
- Trino: 1 Worker statt 3

Override-Datei: `ci/values-k3s-dev.yaml`

Alle Production-Security-Features bleiben aktiv:
- RBAC
- NetworkPolicies
- ExternalSecrets
- TLS (wo möglich)

## Accessing Services

### Port Forwarding (optional)

```bash
kubectl port-forward svc/ingress-nginx 80:80 443:443 -n ingress-nginx
```

### Direct Access

```bash
# Airflow
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080

# Superset
kubectl port-forward svc/data-platform-superset 8088:8088

# OpenMetadata
kubectl port-forward svc/data-platform-openmetadata 8585:8585

# Keycloak
kubectl port-forward svc/data-platform-keycloak 8080:8080
```

## Resource Monitoring

```bash
# Check pod resource usage
kubectl top pods

# Watch deployment status
kubectl get deployments -w

# Check events
kubectl describe pod <pod-name>
```

## Cleanup

```bash
# Remove Data Platform
helm uninstall data-platform

# Remove cluster (WARNING: deletes everything)
k3s-uninstall.sh
```

## Troubleshooting

### "Pod pending" or "ImagePullBackOff"

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### "Storage provisioning timeout"

k3s local-path provisioner is slow on WSL2. Wait or:
```bash
# Check PVCs
kubectl get pvc
```

### "Out of memory"

Increase WSL2 memory in `.wslconfig`:
```ini
[wsl2]
memory=16GB
processors=4
```

Then restart: `wsl --shutdown`

### "Helm timeout"

Increase timeout:
```bash
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml \
  --timeout 20m
```

## Notes

- Dev-environment is NOT suitable for performance testing
- All security features are active (same as Production)
- Some services may be slow on WSL2 (normal, expected)
- Local storage is NOT persistent across `k3s-uninstall.sh`
```

## Akzeptanzkriterien

- [ ] `ci/values-k3s-dev.yaml` vorhanden mit reduzierten Replicas/Resources
- [ ] `scripts/setup-k3s-dev.sh` automatisiert komplettes Setup
- [ ] Script installiert k3s, cert-manager, ingress-nginx, dann Helm Chart
- [ ] `docs/k3s-dev-setup.md` vollständige Anleitung
- [ ] Setup läuft in unter 10 Minuten auf WSL2 (8GB RAM)
- [ ] Alle Storage/RBAC/NetworkPolicies funktionieren auch im Dev-Mode
- [ ] Tests (`helm test`) laufen erfolgreich
- [ ] One-liner funktioniert: `./scripts/setup-k3s-dev.sh`
