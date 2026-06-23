# Multi-Namespace Refactor - Detailed Implementation Plan

**Branch**: `refactor/multi-namespace`  
**Effort**: ~2-3 hours  
**Risk**: LOW (no production cluster exists)

---

## Architecture Change

### BEFORE: Single Namespace
```
Cluster: data-platform
└─ Namespace: data-platform
   ├─ Vault
   ├─ PostgreSQL
   ├─ MinIO
   ├─ Airflow
   ├─ Trino
   ├─ OpenMetadata
   ├─ Superset
   ├─ Metabase
   └─ Keycloak
```

### AFTER: Multi-Namespace (7 namespaces)
```
Cluster: data-platform (FIXED)
├─ Namespace: vault/
│  └─ HashiCorp Vault
├─ Namespace: data-storage/
│  ├─ PostgreSQL
│  └─ MinIO
├─ Namespace: compute/
│  ├─ Airflow
│  ├─ Trino
│  └─ OpenMetadata
├─ Namespace: analytics/
│  ├─ Superset
│  └─ Metabase
├─ Namespace: auth/
│  └─ Keycloak
├─ Namespace: ingress/
│  ├─ ingress-nginx
│  └─ cert-manager
└─ Namespace: monitoring/ (optional, future)
   ├─ Prometheus
   └─ Grafana
```

---

## Step-by-Step Implementation

### Step 1: Add Namespace Definitions to values.yaml
**What**: Add a new `namespaces:` section to define all namespaces

```yaml
namespaces:
  vault: "vault"
  dataStorage: "data-storage"
  compute: "compute"
  analytics: "analytics"
  auth: "auth"
  ingress: "ingress"
  monitoring: "monitoring"  # optional
```

**Files to modify**:
- `values.yaml` - add namespaces section (top level, after global)

**Impact**: Low - just defines namespace names

---

### Step 2: Create Namespace Creation Template
**What**: Create a template that creates all namespaces

**File to create**:
- `templates/namespaces.yaml`

**Content**:
```yaml
{{- if .Values.namespaces }}
{{- range $key, $namespace := .Values.namespaces }}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ $namespace }}
  labels:
    app.kubernetes.io/instance: {{ .Release.Name }}
---
{{- end }}
{{- end }}
```

**Impact**: Low - just creates the namespace resources

---

### Step 3: Update Sub-Chart Deployments (Chart.yaml)
**What**: Add `namespace:` field to each dependency to deploy to correct namespace

**File to modify**:
- `Chart.yaml` dependencies section

**Changes**:
```yaml
dependencies:
  - name: vault
    namespace: {{ .Values.namespaces.vault }}
    
  - name: postgresql
    namespace: {{ .Values.namespaces.dataStorage }}
    
  - name: minio
    namespace: {{ .Values.namespaces.dataStorage }}
    
  - name: airflow
    namespace: {{ .Values.namespaces.compute }}
    
  - name: trino
    namespace: {{ .Values.namespaces.compute }}
    
  # ... etc
```

**Note**: Chart.yaml doesn't support templating directly. Use `values.yaml` overrides instead (Helm 3.x style).

**Better approach**: Override in helm command or values files:
```bash
helm install data-platform . \
  --set vault.namespace=vault \
  --set postgresql.namespace=data-storage \
  # ... etc
```

---

### Step 4: Update Component Values (values/*.yaml)
**What**: Each component needs to reference correct namespace

**Files to modify**:
- `values/vault.yaml` - add namespace field
- `values/postgresql.yaml` - add namespace field
- `values/minio.yaml` - add namespace field
- `values/airflow.yaml` - add namespace field
- `values/trino.yaml` - add namespace field
- `values/openmetadata.yaml` - add namespace field
- `values/superset.yaml` - add namespace field
- `values/metabase.yaml` - add namespace field
- `values/keycloak.yaml` - add namespace field
- `values/external-secrets.yaml` - add namespace field

**Pattern**:
```yaml
# In each values file:
namespace: "{{ .Values.namespaces.COMPONENT_KEY }}"
```

---

### Step 5: Update NetworkPolicies (Per-Namespace)
**What**: Move from global deny-all + component-specific to per-namespace deny-all

**Files to modify/create**:
- `templates/namespaces/default-deny-vault.yaml`
- `templates/namespaces/default-deny-data-storage.yaml`
- `templates/namespaces/default-deny-compute.yaml`
- `templates/namespaces/default-deny-analytics.yaml`
- `templates/namespaces/default-deny-auth.yaml`
- `templates/namespaces/default-deny-ingress.yaml`

**Impact**: Medium - requires understanding of existing NetworkPolicy logic

---

### Step 6: Update ExternalSecrets (Per-Namespace)
**What**: Deploy ExternalSecrets to each namespace that needs secrets

**Files to modify**:
- `templates/externalsecrets/cluster-secret-store.yaml` - may move to each namespace
- `templates/externalsecrets/*.yaml` - reference correct namespace

**Impact**: Medium - each namespace needs its own SecretStore or can reference cluster-level

---

### Step 7: Update RBAC (Per-Namespace)
**What**: Ensure RBAC roles/rolebindings are in correct namespaces

**Files to modify**:
- `templates/rbac/*.yaml` - verify namespace references

**Example**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: airflow-scheduler
  namespace: {{ .Values.namespaces.compute }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: airflow-kubernetes-executor
  namespace: {{ .Values.namespaces.compute }}
# ... rules
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: airflow-kubernetes-executor
  namespace: {{ .Values.namespaces.compute }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: airflow-kubernetes-executor
subjects:
  - kind: ServiceAccount
    name: airflow-scheduler
    namespace: {{ .Values.namespaces.compute }}
```

---

### Step 8: Update Inter-Namespace Service Discovery
**What**: Update connection strings for cross-namespace communication

**Pattern**:
```
service-name.namespace.svc.cluster.local:port
```

**Examples**:
- PostgreSQL from Airflow:
  ```
  postgresql.data-storage.svc.cluster.local:5432
  ```
- Vault from all:
  ```
  vault.vault.svc.cluster.local:8200
  ```
- Keycloak from Airflow:
  ```
  keycloak.auth.svc.cluster.local:8080
  ```

**Files to check**:
- `values/airflow.yaml` - PostgreSQL, Vault, Keycloak connections
- `values/superset.yaml` - PostgreSQL, Trino, Keycloak connections
- `values/metabase.yaml` - PostgreSQL, Trino connections
- `values/openmetadata.yaml` - PostgreSQL, Trino, Vault, Airflow connections
- `values/trino.yaml` - PostgreSQL connections

---

### Step 9: Update Setup Scripts
**What**: Ensure setup scripts deploy to correct namespaces

**Files to modify**:
- `scripts/setup-k3s-dev.sh` - may need updates for namespace context
- `scripts/switch-*.sh` - may need namespace awareness

---

### Step 10: Update Documentation
**What**: Document new multi-namespace architecture

**Files to update**:
- `docs/installation-de.md` - add namespace explanation
- `docs/installation.md` - add namespace explanation
- `docs/architecture-de.md` - add namespace diagram
- `docs/architecture.md` - add namespace diagram
- `README.md` - update namespace references

---

## Testing Strategy

### Local Testing (k3s)
```bash
# 1. Create cluster
./scripts/create-cluster-k3s.sh

# 2. Deploy with namespaces
helm install data-platform . \
  --values values.yaml \
  --values ci/values-k3s-dev.yaml

# 3. Verify namespaces
kubectl get namespaces

# 4. Verify pod distribution
kubectl get pods --all-namespaces

# 5. Verify inter-namespace communication
# Test: Airflow → PostgreSQL
# Test: OpenMetadata → Vault
# Test: Superset → Trino
```

### Validation Checklist
- [ ] All 7 namespaces created
- [ ] All pods in correct namespaces
- [ ] Networking works across namespaces
- [ ] ExternalSecrets synced in each namespace
- [ ] RBAC roles in correct namespaces
- [ ] Ingress routes to correct namespaces
- [ ] Tests pass

---

## Rollback Plan

If something breaks:
```bash
# Go back to v1.0-single-namespace
git checkout v1.0-single-namespace

# Or reset the branch
git reset --hard origin/main
git checkout -b refactor/multi-namespace origin/main
```

---

## Git Strategy

- Work in branch: `refactor/multi-namespace`
- Commit frequently with meaningful messages
- After testing: Create PR to main
- After PR approval: Merge
- Tag as `v1.1-multi-namespace`

---

## Effort Breakdown

| Step | Task | Time | Risk |
|------|------|------|------|
| 1 | Add namespace definitions | 10 min | LOW |
| 2 | Create namespace template | 5 min | LOW |
| 3 | Update Chart.yaml | 5 min | MEDIUM |
| 4 | Update values/*.yaml | 30 min | MEDIUM |
| 5 | Update NetworkPolicies | 20 min | MEDIUM |
| 6 | Update ExternalSecrets | 10 min | MEDIUM |
| 7 | Update RBAC | 10 min | MEDIUM |
| 8 | Update service discovery | 20 min | HIGH |
| 9 | Update scripts | 10 min | LOW |
| 10 | Update documentation | 20 min | LOW |
| | **Testing & validation** | **30 min** | **MEDIUM** |
| | **TOTAL** | **170 min (~2.8h)** | |

---

## Success Criteria

✅ All 7 namespaces created and populated  
✅ All services reachable across namespaces  
✅ All tests pass  
✅ PR passes review  
✅ Documentation updated  
✅ Tagged as v1.1-multi-namespace  

---

## Next Actions

1. Implement Step 1 (namespace definitions)
2. Implement Step 2 (namespace template)
3. Proceed through steps 3-10
4. Test in k3s
5. Create PR
6. Merge after approval
7. Tag final version
