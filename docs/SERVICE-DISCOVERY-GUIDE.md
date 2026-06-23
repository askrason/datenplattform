# Service Discovery Guide - Multi-Namespace DNS

**TICKET-013-015**: Step 8 of multi-namespace refactor  
**Status**: Reference guide (implementation deferred to component configuration)

---

## Cross-Namespace Service DNS Names

In multi-namespace architecture, services in different namespaces need the full DNS name to connect:

### Format
```
<service-name>.<namespace>.svc.cluster.local:<port>
```

### Complete Service Discovery Matrix

| Source | Service | Destination Namespace | Service | Port | DNS Name |
|--------|---------|--------|---|------|----------|
| Airflow | compute/ | PostgreSQL | data-storage/ | 5432 | `postgresql.data-storage.svc.cluster.local:5432` |
| Airflow | compute/ | MinIO | data-storage/ | 9000 | `minio.data-storage.svc.cluster.local:9000` |
| Airflow | compute/ | Keycloak | auth/ | 8080/8443 | `keycloak.auth.svc.cluster.local:8080` |
| Airflow | compute/ | Vault | vault/ | 8200 | `vault.vault.svc.cluster.local:8200` |
| Airflow | compute/ | Trino | compute/ | 8080 | `trino.compute.svc.cluster.local:8080` (same NS) |
| Airflow | compute/ | OpenMetadata | compute/ | 8585 | `openmetadata.compute.svc.cluster.local:8585` (same NS) |
|
| Trino | compute/ | PostgreSQL | data-storage/ | 5432 | `postgresql.data-storage.svc.cluster.local:5432` |
| Trino | compute/ | MinIO | data-storage/ | 9000 | `minio.data-storage.svc.cluster.local:9000` |
| Trino | compute/ | Keycloak | auth/ | 8080 | `keycloak.auth.svc.cluster.local:8080` |
|
| OpenMetadata | compute/ | PostgreSQL | data-storage/ | 5432 | `postgresql.data-storage.svc.cluster.local:5432` |
| OpenMetadata | compute/ | MinIO | data-storage/ | 9000 | `minio.data-storage.svc.cluster.local:9000` |
| OpenMetadata | compute/ | Vault | vault/ | 8200 | `vault.vault.svc.cluster.local:8200` |
| OpenMetadata | compute/ | Airflow | compute/ | 8080 | `airflow.compute.svc.cluster.local:8080` (same NS) |
| OpenMetadata | compute/ | Trino | compute/ | 8080 | `trino.compute.svc.cluster.local:8080` (same NS) |
| OpenMetadata | compute/ | Keycloak | auth/ | 8080 | `keycloak.auth.svc.cluster.local:8080` |
|
| Superset | analytics/ | PostgreSQL | data-storage/ | 5432 | `postgresql.data-storage.svc.cluster.local:5432` |
| Superset | analytics/ | Trino | compute/ | 8080 | `trino.compute.svc.cluster.local:8080` |
| Superset | analytics/ | Keycloak | auth/ | 8080 | `keycloak.auth.svc.cluster.local:8080` |
| Superset | analytics/ | Redis | analytics/ | 6379 | `redis.analytics.svc.cluster.local:6379` (same NS) |
|
| Metabase | analytics/ | PostgreSQL | data-storage/ | 5432 | `postgresql.data-storage.svc.cluster.local:5432` |
| Metabase | analytics/ | Trino | compute/ | 8080 | `trino.compute.svc.cluster.local:8080` |
| Metabase oauth2-proxy | analytics/ | Keycloak | auth/ | 8080 | `keycloak.auth.svc.cluster.local:8080` |
|
| Keycloak | auth/ | PostgreSQL | data-storage/ | 5432 | `postgresql.data-storage.svc.cluster.local:5432` |
| Keycloak | auth/ | Vault | vault/ | 8200 | `vault.vault.svc.cluster.local:8200` |
|
| ESO | vault/ | Vault | vault/ | 8200 | `vault.vault.svc.cluster.local:8200` (same NS, but explicit for clarity) |
|
| Ingress-nginx | ingress/ | Airflow | compute/ | 8080 | `airflow.compute.svc.cluster.local:8080` |
| Ingress-nginx | ingress/ | Superset | analytics/ | 8088 | `superset.analytics.svc.cluster.local:8088` |
| Ingress-nginx | ingress/ | Metabase | analytics/ | 3000 | `metabase.analytics.svc.cluster.local:3000` |
| Ingress-nginx | ingress/ | OpenMetadata | compute/ | 8585 | `openmetadata.compute.svc.cluster.local:8585` |
| Ingress-nginx | ingress/ | MinIO Console | data-storage/ | 9001 | `minio.data-storage.svc.cluster.local:9001` |
| Ingress-nginx | ingress/ | Keycloak | auth/ | 8080 | `keycloak.auth.svc.cluster.local:8080` |

---

## Same-Namespace vs Cross-Namespace DNS

### Same Namespace (Optional)
Services in the same namespace can use the short name:
```
postgresql.svc.cluster.local:5432
```

Kubernetes DNS resolves this to:
```
postgresql.<current-namespace>.svc.cluster.local:5432
```

### Cross-Namespace (Required)
Services in different namespaces MUST use the full name:
```
postgresql.data-storage.svc.cluster.local:5432
```

---

## Implementation Notes

### 1. ExternalSecrets: Vault Endpoint
Already updated in `cluster-secret-store.yaml`:
```yaml
server: "http://{{ .Release.Name }}-vault.{{ .Values.namespaces.vault }}.svc.cluster.local:8200"
```

### 2. Component Configuration Values
Service endpoint configuration must be updated in component values:
- `values/airflow.yaml` - PostgreSQL, Trino, Keycloak endpoints
- `values/superset.yaml` - Trino, PostgreSQL, Keycloak endpoints
- `values/metabase.yaml` - Trino, PostgreSQL endpoints
- `values/openmetadata.yaml` - PostgreSQL, Trino, Airflow endpoints
- `values/trino.yaml` - PostgreSQL catalogs
- `values/keycloak.yaml` - PostgreSQL endpoint

### 3. Ingress Configuration
Ingress rules must route to correct namespace service endpoints:
```yaml
backend:
  service:
    name: airflow
    namespace: compute
    port:
      number: 8080
```

### 4. Environment Variables in Containers
Container env variables referencing services must use full DNS:
```yaml
env:
  - name: DATABASE_HOST
    value: "postgresql.data-storage.svc.cluster.local"
  - name: DATABASE_PORT
    value: "5432"
```

---

## Testing Service Discovery

### Verify DNS Resolution in Pod
```bash
# From any pod in the cluster
kubectl exec -it <pod> -n <namespace> -- nslookup postgresql.data-storage.svc.cluster.local

# Expected output:
# Name:      postgresql.data-storage.svc.cluster.local
# Address:   10.x.x.x  (ClusterIP)
```

### Test Connectivity
```bash
# From within a pod
kubectl exec -it <pod> -n <namespace> -- curl postgresql.data-storage.svc.cluster.local:5432
# Should respond (even if curl fails, TCP connection proves DNS works)
```

### Check Service Endpoints
```bash
# See all services in a namespace
kubectl get svc -n data-storage

# See specific service details
kubectl get svc postgresql -n data-storage -o yaml
```

---

## Kubernetes Service DNS Details

All Kubernetes services are resolvable via DNS as:
```
<service-name>.<namespace>.svc.cluster.local
```

With typical DNS search paths:
- `svc.cluster.local` (within same namespace)
- `cluster.local`
- `<internal-search-path>`

For cross-namespace access, always use the full name to be explicit.

---

## Troubleshooting

### Connection Refused
- Check service exists: `kubectl get svc -n <namespace>`
- Check service has endpoints: `kubectl describe svc <name> -n <namespace>`
- Check NetworkPolicy allows traffic

### DNS Not Resolving
- Check CoreDNS is running: `kubectl get pods -n kube-system | grep coredns`
- Check if pod can reach DNS server (port 53)
- Try using pod IP instead of service name (verify with `kubectl get endpoints`)

### Certificate Errors
- If using internal HTTPS, service certificate must match DNS name
- Use full namespace-aware DNS name in certificate

---

## Implementation Status

**Step 8 of multi-namespace refactor**

This guide documents the service discovery requirements. Actual implementation is deferred to:
1. Review of component values files for endpoint configuration
2. Update of ingress routing rules
3. Verification of connectivity through helm template + testing

See `NAMESPACE-ASSIGNMENTS.md` for the complete refactor plan.

