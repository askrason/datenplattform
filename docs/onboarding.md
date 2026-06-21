# Onboarding for New Developers

## Prerequisites (Local)

```bash
# Required tools
kubectl version --client
helm version
kind --version
git --version

# Optional
docker --version
vault version (for local Vault testing)
```

## Setup Steps

### 1. Clone Repository
```bash
git clone https://github.com/askrason/datenplattform.git
cd datenplattform
```

### 2. Read CLAUDE.md
```bash
cat CLAUDE.md
# Focus on:
# - Security Baseline (NON-NEGOTIABLE)
# - Coding Conventions
# - ADRs (Architecture Decision Records)
```

### 3. Start Kind Cluster
```bash
kind create cluster --config ci/kind-config.yaml
kind get clusters
```

### 4. Install Dependencies
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add apache https://airflow.apache.org
helm repo add trinodb https://trinodb.github.io/charts
helm repo update
helm dependency update
```

### 5. Deploy Chart (Local Test)
```bash
helm install data-platform . \
  --values values.yaml \
  --wait --timeout 10m
```

### 6. Verify Deployment
```bash
kubectl get pods
kubectl get svc
helm test data-platform --timeout 5m
```

## Key Conventions

1. **Read CLAUDE.md** before making any changes
2. **No plaintext secrets** in values.yaml → use Vault + ExternalSecret
3. **Security exceptions always commented** (readOnlyRootFilesystem: false)
4. **Test NetworkPolicies** before PR
5. **Resource limits required** for every container

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| "Klartext-Passwort in values.yaml" | Move to Vault, reference via ExternalSecret |
| "Pod won't start" | Check readOnlyRootFilesystem + emptyDir volumes |
| "ESO Secret stuck" | Is Vault unsealed? Does Pod have RBAC for Secrets? |
| "OIDC Login fails" | Keycloak Client-Secret in Vault? Redirect-URI correct? |
| "NetworkPolicy too strict" | Add ingress/egress rules, test with curl from test-pod |

## Typical Workflow

1. Create feature branch: `git checkout -b feature/TICKET-XXX`
2. Make changes in values/*.yaml or templates/
3. Run validation: `./scripts/validate.sh`
4. Test locally: `helm upgrade data-platform . --dry-run`
5. Commit: `git commit -am "feat: TICKET-XXX - Description"`
6. Push: `git push origin feature/TICKET-XXX`
7. Create PR on GitHub
8. CI runs lint + test
9. Merge after review

## Documentation Files (READ FIRST)

- `CLAUDE.md` - Project conventions & ADRs
- `docs/architecture.md` - System design
- `docs/networking.md` - Network policies & connectivity
- `docs/operations.md` - Runbook for operators
- `docs/keycloak-setup.md` - Keycloak deployment steps
- `docs/metabase-setup.md` - Metabase post-deploy config

## Getting Help

- Check existing docs/ files
- Read CLAUDE.md ADR sections
- Search GitHub issues
- Ask in team Slack channel
