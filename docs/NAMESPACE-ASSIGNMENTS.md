# Multi-Namespace Assignments - Complete Reference

**Branch**: `refactor/multi-namespace`  
**Status**: Step 4/10 complete - Component values annotated  
**Next**: Step 5 - NetworkPolicies refactor  

---

## Namespace Deployment Matrix

| Namespace | Components | Count | Helm Sub-Charts | Service Ports |
|-----------|-----------|-------|-----------------|----------------|
| **vault/** | Vault | 1 | vault | 8200 (API), 8201 (Raft) |
| **data-storage/** | PostgreSQL, MinIO | 2 | postgresql, minio | 5432 (DB), 9000/9001 (S3) |
| **compute/** | Airflow, Trino, OpenMetadata | 3 | airflow, trino, openmetadata | 8080, 8585 |
| **analytics/** | Superset, Metabase | 2 | superset, metabase | 8088, 3000 |
| **auth/** | Keycloak | 1 | keycloak | 8080 |
| **ingress/** | ingress-nginx, cert-manager | 2 | (external) | 80, 443 |
| **monitoring/** | Prometheus, Grafana | 2 | (future) | 9090, 3000 |

---

## NetworkPolicy Refactor Strategy

### CURRENT STATE (Single Namespace)
```
Namespace: data-platform
├─ NetworkPolicy: vault-netpol.yaml (namespace: data-platform)
├─ NetworkPolicy: postgresql-netpol.yaml (namespace: data-platform)
├─ NetworkPolicy: minio-netpol.yaml (namespace: data-platform)
├─ NetworkPolicy: airflow-netpol.yaml (namespace: data-platform)
└─ ... (all others in same namespace)
```

### TARGET STATE (Multi-Namespace)
```
Namespace: vault/
├─ NetworkPolicy: vault-netpol.yaml (namespace: vault)
│  ├─ Allow: external-secrets from vault/ (same namespace)
│  └─ Egress: K8s API, DNS

Namespace: data-storage/
├─ NetworkPolicy: default-deny.yaml (deny-all except Ingress)
├─ NetworkPolicy: postgresql-netpol.yaml (namespace: data-storage)
│  ├─ Allow: Airflow from compute/
│  ├─ Allow: Superset from analytics/
│  ├─ Allow: Metabase from analytics/
│  ├─ Allow: OpenMetadata from compute/
│  └─ Allow: Keycloak from auth/
├─ NetworkPolicy: minio-netpol.yaml (namespace: data-storage)
│  ├─ Allow: Airflow from compute/
│  ├─ Allow: Trino from compute/
│  └─ Allow: OpenMetadata from compute/
└─ Egress: DNS, K8s API

Namespace: compute/
├─ NetworkPolicy: default-deny.yaml
├─ NetworkPolicy: airflow-netpol.yaml
│  ├─ Allow: PostgreSQL to data-storage/ (5432)
│  ├─ Allow: MinIO to data-storage/ (9000)
│  ├─ Allow: Vault to vault/ (8200)
│  ├─ Allow: Keycloak to auth/ (8080)
│  └─ Allow: Ingress from ingress/ (8080)
├─ NetworkPolicy: trino-netpol.yaml
│  ├─ Allow: PostgreSQL to data-storage/ (5432)
│  ├─ Allow: MinIO to data-storage/ (9000)
│  └─ Allow: Keycloak to auth/ (8080)
└─ NetworkPolicy: openmetadata-netpol.yaml
   ├─ Allow: PostgreSQL to data-storage/ (5432)
   ├─ Allow: MinIO to data-storage/ (9000)
   ├─ Allow: Vault to vault/ (8200)
   ├─ Allow: Airflow to compute/ (8080)
   ├─ Allow: Trino to compute/ (8080)
   └─ Allow: Keycloak to auth/ (8080)

Namespace: analytics/
├─ NetworkPolicy: default-deny.yaml
├─ NetworkPolicy: superset-netpol.yaml
│  ├─ Allow: PostgreSQL to data-storage/ (5432)
│  ├─ Allow: Trino to compute/ (8080)
│  ├─ Allow: Keycloak to auth/ (8080)
│  └─ Allow: Ingress from ingress/ (8088)
└─ NetworkPolicy: metabase-netpol.yaml
   ├─ Allow: PostgreSQL to data-storage/ (5432)
   ├─ Allow: Trino to compute/ (8080)
   └─ Allow: Ingress from ingress/ (3000)

Namespace: auth/
├─ NetworkPolicy: default-deny.yaml
└─ NetworkPolicy: keycloak-netpol.yaml
   ├─ Allow: All namespaces to auth/ (8080) — for OIDC token validation
   └─ Allow: Vault to vault/ (8200)

Namespace: ingress/
├─ NetworkPolicy: allow-external.yaml
│  ├─ Allow: External traffic → Port 80, 443
└─ NetworkPolicy: to-services.yaml
   ├─ Allow to: vault/ (none)
   ├─ Allow to: data-storage/ (none)
   ├─ Allow to: compute/ (8080 → airflow)
   ├─ Allow to: analytics/ (8088 → superset, 3000 → metabase)
   ├─ Allow to: auth/ (8080 → keycloak)
   └─ Allow to: monitoring/ (none)
```

---

## Cross-Namespace Communication Rules

### FROM → TO Rules (sorted by source)

```
AIRFLOW (compute/) → PostgreSQL (data-storage/)    : TCP 5432
AIRFLOW (compute/) → MinIO (data-storage/)         : TCP 9000
AIRFLOW (compute/) → Vault (vault/)                : TCP 8200
AIRFLOW (compute/) → Keycloak (auth/)              : TCP 8080

TRINO (compute/) → PostgreSQL (data-storage/)      : TCP 5432
TRINO (compute/) → MinIO (data-storage/)           : TCP 9000
TRINO (compute/) → Keycloak (auth/)                : TCP 8080

OPENMETADATA (compute/) → PostgreSQL (data-storage/) : TCP 5432
OPENMETADATA (compute/) → MinIO (data-storage/)    : TCP 9000
OPENMETADATA (compute/) → Vault (vault/)           : TCP 8200
OPENMETADATA (compute/) → Airflow (compute/)       : TCP 8080
OPENMETADATA (compute/) → Trino (compute/)         : TCP 8080
OPENMETADATA (compute/) → Keycloak (auth/)         : TCP 8080

SUPERSET (analytics/) → PostgreSQL (data-storage/) : TCP 5432
SUPERSET (analytics/) → Trino (compute/)           : TCP 8080
SUPERSET (analytics/) → Keycloak (auth/)           : TCP 8080

METABASE (analytics/) → PostgreSQL (data-storage/) : TCP 5432
METABASE (analytics/) → Trino (compute/)           : TCP 8080

KEYCLOAK (auth/) → PostgreSQL (data-storage/)      : TCP 5432
KEYCLOAK (auth/) → Vault (vault/)                  : TCP 8200

ESO (vault/) → Vault (vault/)                      : TCP 8200 (same NS)

INGRESS (ingress/) → Airflow (compute/)            : TCP 8080
INGRESS (ingress/) → Superset (analytics/)         : TCP 8088
INGRESS (ingress/) → Metabase (analytics/)         : TCP 3000
INGRESS (ingress/) → Keycloak (auth/)              : TCP 8080

ALL → Keycloak (auth/)                             : TCP 8080 (OIDC token validation)
ALL → K8s API                                      : TCP 443 (TokenReview, API access)
ALL → DNS                                          : UDP 53, TCP 53
```

---

## NetworkPolicy Template Updates Required

### Files to Modify (Step 5)

1. **Default-Deny per Namespace**
   - `templates/networkpolicies/namespace-default-deny-vault.yaml` (NEW)
   - `templates/networkpolicies/namespace-default-deny-data-storage.yaml` (NEW)
   - `templates/networkpolicies/namespace-default-deny-compute.yaml` (NEW)
   - `templates/networkpolicies/namespace-default-deny-analytics.yaml` (NEW)
   - `templates/networkpolicies/namespace-default-deny-auth.yaml` (NEW)
   - `templates/networkpolicies/namespace-default-deny-ingress.yaml` (NEW)

2. **Namespace-Scoped Component NetPols**
   - `templates/networkpolicies/vault-netpol.yaml` → Update `namespace:` field
   - `templates/networkpolicies/postgresql-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/minio-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/airflow-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/trino-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/openmetadata-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/superset-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/metabase-netpol.yaml` → Update, add cross-namespace rules
   - `templates/networkpolicies/keycloak-netpol.yaml` → Update, add cross-namespace rules

3. **Ingress-Specific NetPols**
   - `templates/networkpolicies/ingress-netpol.yaml` (NEW)

---

## Implementation Details

### Key Changes per NetPol

#### 1. Namespace Field
**BEFORE**:
```yaml
metadata:
  namespace: {{ .Release.Namespace }}  # data-platform
```

**AFTER**:
```yaml
metadata:
  namespace: {{ .Values.namespaces.compute }}  # compute
```

#### 2. Cross-Namespace Pod Selectors
**BEFORE** (same namespace):
```yaml
- from:
  - podSelector:
      matchLabels:
        app: external-secrets
```

**AFTER** (different namespace):
```yaml
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: {{ .Values.namespaces.vault }}
    podSelector:
      matchLabels:
        app.kubernetes.io/name: external-secrets
```

#### 3. DNS & K8s API (Egress)
Bleibt gleich - alle Namespaces brauchen Zugriff auf DNS und K8s API:
```yaml
egress:
  - to: [namespaceSelector: {}]
    ports: [TCP 443]  # K8s API

  - to: [podSelector: {}]
    ports: [UDP 53, TCP 53]  # DNS
```

---

## Commit Strategy for Step 5

1. Create `namespace-default-deny-*.yaml` templates (one per namespace)
2. Update existing NetPol files with new namespace references
3. Add cross-namespace ingress rules (from other namespaces)
4. Single commit: "refactor: Step 5 - NetworkPolicies per-namespace"
5. Test with helm template to verify generated YAML

---

## Validation Checklist

- [ ] All 7 namespace default-deny policies created
- [ ] All 9 component NetPols updated with correct namespace
- [ ] All cross-namespace rules use namespaceSelector + podSelector
- [ ] Helm template generates valid YAML
- [ ] No conflicting rules
- [ ] Keycloak ingress allows from all namespaces
- [ ] Ingress routes correctly to services in other namespaces

