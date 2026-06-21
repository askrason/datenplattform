# TICKET-004: Vault + External Secrets Operator

## Ziel
HashiCorp Vault und den External Secrets Operator (ESO) als zentrale
Secrets-Management-Infrastruktur deployen. Nach diesem Ticket können alle
nachfolgenden Komponenten ihre Secrets sicher aus Vault beziehen.
Dieses Ticket ist Voraussetzung für TICKET-005 bis TICKET-010.

## Voraussetzungen
- TICKET-001 abgeschlossen
- CLAUDE.md gelesen

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001, TICKET-002, TICKET-003
Neue Dateien: values/vault.yaml, values/external-secrets.yaml,
  templates/externalsecrets/cluster-secret-store.yaml,
  templates/rbac/vault-auth-rbac.yaml,
  docs/vault-setup.md
```

## Architektur-Überblick

```
Kubernetes ServiceAccount (jeder Pod)
        ↓ JWT Token
Vault Kubernetes Auth Method
        ↓ Vault Token (kurzlebig)
External Secrets Operator (ClusterSecretStore)
        ↓ liest Secrets
K8s Secret-Objekte (im jeweiligen Namespace)
        ↓ mountet als Env/Volume
Airflow / PostgreSQL / Trino / etc.
```

## Zu erstellende / zu ändernde Dateien

### 1. `values/vault.yaml`

**Modus:** HA (High Availability) mit 3 Replicas, Raft-Storage

```yaml
vault:
  enabled: true
  server:
    ha:
      enabled: true
      replicas: 3
      raft:
        enabled: true
        config: |
          ui = true
          listener "tcp" {
            tls_disable = 1
            address = "[::]:8200"
            cluster_address = "[::]:8201"
          }
          storage "raft" {
            path = "/vault/data"
          }
          service_registration "kubernetes" {}
    podSecurityContext:
      <<: *defaultPodSecurityContext
      runAsUser: 100
      fsGroup: 1000
    securityContext:
      <<: *defaultSecurityContext
      # AUSNAHME: Vault schreibt Raft-Daten und Audit-Logs
      readOnlyRootFilesystem: false
      capabilities:
        add: [IPC_LOCK]   # Vault benötigt IPC_LOCK für Memory-Locking (mlock)
        drop: [ALL]       # Alle anderen Capabilities gedroppt
    resources:
      requests: { cpu: "250m", memory: "256Mi" }
      limits:   { cpu: "1000m", memory: "1Gi" }
    persistentVolumeClaimRetentionPolicy:
      whenDeleted: Retain   # Daten bei Chart-Deinstallation behalten!
    dataStorage:
      enabled: true
      size: 10Gi
      storageClass: "{{ .Values.global.storageClass }}"

  ui:
    enabled: true   # Vault UI via Ingress erreichbar

  injector:
    enabled: false  # Wir nutzen ESO statt Vault Agent Injector
```

**Wichtiger Hinweis im Template-Kommentar:**
```
# VAULT UNSEAL: Nach Deployment muss Vault manuell initialisiert werden.
# Prozess: vault operator init → Root Token + Unseal Keys sicher verwahren.
# Für Production: Vault Auto Unseal via Cloud KMS konfigurieren.
# Dokumentation: docs/vault-setup.md
```

### 2. `values/external-secrets.yaml`

```yaml
external-secrets:
  enabled: true
  installCRDs: true
  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1000
  securityContext:
    <<: *defaultSecurityContext
  resources:
    requests: { cpu: "100m", memory: "128Mi" }
    limits:   { cpu: "500m", memory: "256Mi" }
  webhook:
    podSecurityContext:
      <<: *defaultPodSecurityContext
    securityContext:
      <<: *defaultSecurityContext
  certController:
    podSecurityContext:
      <<: *defaultPodSecurityContext
    securityContext:
      <<: *defaultSecurityContext
```

### 3. `templates/externalsecrets/cluster-secret-store.yaml`

ClusterSecretStore der sich via Kubernetes Auth bei Vault authentifiziert:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://{{ .Release.Name }}-vault:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets-operator"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "{{ .Release.Namespace }}"
```

> Hinweis: `version: "v2"` bedeutet, dass ESO das KV-v2-typische `data/`-
> Segment selbst ergänzt. Alle `remoteRef.key`-Angaben in den übrigen
> Tickets folgen deshalb einheitlich dem Schema
> `secret/data-platform/<komponente>/<key>` – OHNE zusätzliches `data/`.

### 4. `templates/rbac/vault-auth-rbac.yaml`

ServiceAccount + ClusterRoleBinding für ESO, damit Vault die K8s Token validieren kann:

```yaml
# ServiceAccount für External Secrets Operator
# ClusterRole: tokenreview.k8s.io (create) – damit Vault Tokens validieren kann
# ClusterRoleBinding: bindet ESO ServiceAccount an die ClusterRole
```

### 5. `docs/vault-setup.md`

Schritt-für-Schritt-Anleitung für initiales Vault-Setup nach dem ersten Deployment:

```markdown
## Vault Initialisierung (einmalig nach erstem Deployment)

### 1. Vault initialisieren
kubectl exec -n <namespace> vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-init.json
# → vault-init.json SICHER VERWAHREN (enthält Root Token + Unseal Keys)

### 2. Vault unsealen (auf allen 3 Replicas)
for i in 0 1 2; do
  kubectl exec -n <namespace> vault-$i -- vault operator unseal <KEY_1>
  kubectl exec -n <namespace> vault-$i -- vault operator unseal <KEY_2>
  kubectl exec -n <namespace> vault-$i -- vault operator unseal <KEY_3>
done

### 3. Kubernetes Auth aktivieren
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

### 4. ESO-Rolle erstellen
vault policy write external-secrets-operator - <<EOF
path "secret/data/data-platform/*" { capabilities = ["read"] }
EOF
vault write auth/kubernetes/role/external-secrets-operator \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=<namespace> \
  policies=external-secrets-operator \
  ttl=1h

### 5. Secrets befüllen
vault kv put secret/data-platform/postgresql \
  root-password="<sicheres-passwort>" \
  airflow-password="..." \
  ...
```

### 6. `templates/networkpolicies/vault-netpol.yaml`

Ingress auf Port 8200 erlaubt von:
- External Secrets Operator
- Vault-eigene Pods (Raft-Cluster-Kommunikation Port 8201)

Ingress Port 8200 vom Ingress Controller (für Vault UI).

Egress: Vault → K8s API Server (für Kubernetes Auth Token Validation).

## Vault Secret-Struktur (Konvention für das gesamte Projekt)

```
secret/data-platform/
├── postgresql/
│   ├── root-password
│   ├── airflow-password
│   ├── openmetadata-password
│   ├── superset-password
│   ├── metabase-password
│   └── keycloak-password
├── minio/
│   ├── root-user
│   ├── root-password
│   ├── airflow-secret-key
│   ├── trino-secret-key
│   └── openmetadata-secret-key
├── airflow/
│   ├── fernet-key
│   └── webserver-secret-key
├── trino/
│   └── (falls interne Auth aktiviert)
├── superset/
│   └── secret-key
├── metabase/
│   └── encryption-key
└── keycloak/
    ├── admin-password
    └── db-password
```

## Akzeptanzkriterien

- [ ] Vault deployed im HA-Modus (3 Replicas, Raft-Storage)
- [ ] External Secrets Operator deployed und läuft
- [ ] `ClusterSecretStore` vault-backend erstellt
- [ ] `docs/vault-setup.md` vollständig und ausführbar
- [ ] RBAC für ESO-Vault-Auth vorhanden
- [ ] NetworkPolicy: nur ESO und Vault-interne Pods erreichen Port 8200
- [ ] IPC_LOCK Capability korrekt konfiguriert (mit Kommentar)
- [ ] `vault.injector.enabled: false` (wir nutzen ESO)
- [ ] Vault-UI via Ingress erreichbar

## Nicht in diesem Ticket
- Befüllen der Vault-Secrets (geschieht manuell nach Deployment, siehe vault-setup.md)
- Komponenten-spezifische ExternalSecret-Ressourcen (in jeweiligen Tickets)
