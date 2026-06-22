# Development Secrets Bootstrap-Anleitung

Für lokale Entwicklungsumgebungen ohne Vault (TICKET-014: Engineer, TICKET-015: Analyst).

---

## Warum Bootstrap-Skript?

Wenn `vault.enabled: false` und `external-secrets.enabled: false`, erwartet das Chart Kubernetes Secrets bei:
- `data-platform-postgresql-credentials`
- `data-platform-airflow-db-credentials`
- `data-platform-minio-credentials`
- `data-platform-trino-credentials`
- `data-platform-superset-db-credentials` (analyst)
- `data-platform-metabase-db-credentials` (analyst)

Ohne diese bleiben Pods in `CreateContainerConfigError` hängen.

**Lösung:** `scripts/bootstrap-dev-secrets.sh` generiert zufällige Passwörter und erstellt Secrets via `kubectl`.

---

## Schnellstart

### Engineer-Profil

```bash
# 1. Starte dein Cluster
k3s  # oder minikube start, kind create cluster, etc.

# 2. Erstelle Secrets
./scripts/bootstrap-dev-secrets.sh engineer

# 3. Deploy
helm install data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml
```

### Analyst-Profil

```bash
./scripts/bootstrap-dev-secrets.sh analyst

helm install data-platform . \
  --values values.yaml \
  --values ci/values-analyst-dev.yaml
```

---

## Was wird erstellt

### Engineer Secrets

```
data-platform-postgresql-credentials
  username: postgres
  password: <zufällig>

data-platform-airflow-db-credentials
  username: airflow
  password: <zufällig>

data-platform-airflow-oidc-credentials
  client_id: airflow-dev
  client_secret: dev-stub-secret-no-keycloak

data-platform-minio-credentials
  rootUser: minioadmin
  rootPassword: <zufällig>

data-platform-trino-credentials
  username: admin
  password: <zufällig>
```

### Analyst Secrets

```
data-platform-postgresql-credentials
  username: postgres
  password: <zufällig>

data-platform-trino-credentials
  username: admin
  password: <zufällig>

data-platform-superset-db-credentials
  username: superset
  password: <zufällig>

data-platform-metabase-db-credentials
  username: metabase
  password: <zufällig>
```

---

## Wichtige Hinweise

### ✅ Akzeptable Nutzung

- Nur lokale Entwicklung (ephemerale k3s/minikube Cluster)
- Temporär, niemals in Git committed
- Unterschiedlich von Produktion Secret-Management

### ❌ NIEMALS verwenden für

- Shared Clusters
- Produktion Deployments
- Multi-User Systeme

---

## Secrets löschen

Beim Abbau des Clusters:

```bash
# Entferne einzelne Secrets
kubectl delete secret data-platform-postgresql-credentials
kubectl delete secret data-platform-airflow-db-credentials
# ... etc

# Oder entferne alle auf einmal
kubectl delete secret -l app.kubernetes.io/instance=data-platform

# Oder lösche den ganzen Cluster
k3s server --disable=servicelb  # Stoppe k3s
# ... oder minikube delete, kind delete cluster, etc.
```

---

## Fehlerbehebung

### "Secret already exists"

```bash
# Secrets sind idempotent-sicher. Skript überspringt, falls vorhanden.
# Zum Regenerieren:
kubectl delete secret data-platform-postgresql-credentials
./scripts/bootstrap-dev-secrets.sh engineer
```

### "kubectl: command not found"

```bash
# Installiere kubectl oder konfiguriere deine Shell, um k3s' bundelte Version zu nutzen:
export PATH=/usr/local/bin:$PATH  # k3s installiert hier
which kubectl
```

### "Not connected to a Kubernetes cluster"

```bash
# Starte dein Cluster:
k3s  # oder:
minikube start
# oder:
kind create cluster --config ci/kind-config.yaml
```

### Pods immer noch in CreateContainerConfigError

```bash
# Überprüfe, welche Secrets fehlen:
kubectl get pods -o wide
kubectl describe pod <pod-name>

# Siehe Logs:
kubectl logs <pod-name>

# Führe Bootstrap neu aus:
./scripts/bootstrap-dev-secrets.sh engineer
```

---

## Siehe auch

- **Engineer Setup**: `docs/engineer-dev-setup.md`
- **Analyst Setup**: `docs/analyst-dev-setup.md`
- **Full-Stack Setup**: `docs/k3s-dev-setup.md`
- **Sicherheitshinweis**: CLAUDE.md, Known Issue #7
