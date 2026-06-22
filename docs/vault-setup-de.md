# Vault Initialisierung & Setup

Nach dem Deployment von TICKET-004 muss Vault manuell initialisiert werden.
Diese Anleitung führt durch den vollständigen Setup-Prozess.

## Voraussetzungen

- `helm install` oder `helm upgrade` erfolgreich durchgeführt
- `kubectl` mit Zugriff auf den Cluster
- `vault` CLI lokal installiert (optional, aber empfohlen)
- Vault Pods sind im Running-State: `kubectl get pods -l app.kubernetes.io/name=vault`

## Phase 1: Vault Initialisierung (einmalig)

### 1.1 Vault Operator Init

Verbinde dich zum Master-Pod und initialisiere Vault:

```bash
NAMESPACE="default"  # oder euer Namespace
RELEASE_NAME="data-platform"

# Vault initialisieren
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- \
  vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json > vault-init.json
```

**Wichtig:** `vault-init.json` enthält den Root Token und Unseal Keys.
Diese Datei MUSS sicher verwahrt werden (z.B. in einem Secret Storage):
- Root Token → nicht verlieren (für manuelle Admin-Operationen nötig)
- Unseal Keys → mindestens 3 von 5 Keys brauchbar zum Unseal

Speichere die Keys separat:

```bash
# Root Token extrahieren
cat vault-init.json | jq -r '.root_token' > root-token.txt

# Unseal Keys extrahieren
cat vault-init.json | jq -r '.unseal_keys_b64[] ' > unseal-keys.txt
```

### 1.2 Vault Unsealen

Nach Init sind alle 3 Vault-Replicas **sealed**. Jede Replica muss einzeln unsealed werden:

```bash
# Keys aus unseal-keys.txt lesen
KEY_1=$(sed -n '1p' unseal-keys.txt)
KEY_2=$(sed -n '2p' unseal-keys.txt)
KEY_3=$(sed -n '3p' unseal-keys.txt)

# Auf allen 3 Replicas unseal durchführen
for i in 0 1 2; do
  echo "Unsealing replica $i..."
  kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-${i}" -- \
    vault operator unseal "$KEY_1"
  kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-${i}" -- \
    vault operator unseal "$KEY_2"
  kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-${i}" -- \
    vault operator unseal "$KEY_3"
done

# Statusprüfung: alle Replicas sollten "Unsealed" zeigen
for i in 0 1 2; do
  kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-${i}" -- \
    vault status
done
```

### 1.3 Root Token speichern (optional)

Wenn Sie lokal mit `vault` CLI arbeiten möchten:

```bash
export VAULT_ADDR="http://vault.example.com:8200"  # oder Port-Forward
export VAULT_TOKEN=$(cat root-token.txt)

# Test
vault status
```

---

## Phase 2: Kubernetes Authentication Setup

Dies konfiguriert Vault so, dass ESO sich mit K8s ServiceAccount Tokens authentifizieren kann.

### 2.1 Kubernetes Auth Methode aktivieren

```bash
ROOT_TOKEN=$(cat root-token.txt)

kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- \
  vault auth enable kubernetes
```

### 2.2 Kubernetes Auth Method konfigurieren

Vault benötigt Details über den K8s API Server:

```bash
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- \
  vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

Falls das nicht funktioniert (z.B. in Port-Forward-Szenarios), manuell konfigurieren:

```bash
# API Server Details ermitteln
kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}'  # IP
kubectl get svc kubernetes -n default -o jsonpath='{.spec.ports[0].port}'  # Port

# Zertifikat kopieren
kubectl get secret -n kube-system -l component=ca -o jsonpath='{.items[0].data.ca\.crt}' | base64 -d > ca.crt

# Manuell in Vault eintragen
vault write auth/kubernetes/config \
  kubernetes_host="https://10.0.0.1:443" \
  kubernetes_ca_cert=@ca.crt \
  token_reviewer_jwt=$(kubectl get secret -n "$NAMESPACE" -l app.kubernetes.io/name=external-secrets \
    -o jsonpath='{.items[0].data.token}' | base64 -d)
```

---

## Phase 3: ESO-Rolle und Policy

### 3.1 Policy erstellen

Diese Policy gestattet ESO, Secrets unter `secret/data-platform/*` zu lesen:

```bash
vault policy write external-secrets-operator - <<'EOF'
path "secret/data-platform/*" {
  capabilities = ["read", "list"]
}
EOF
```

### 3.2 Kubernetes Auth Rolle binden

```bash
vault write auth/kubernetes/role/external-secrets-operator \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces="$NAMESPACE" \
  policies="external-secrets-operator" \
  ttl=1h
```

---

## Phase 4: Secrets befüllen

Nun können Secrets für jede Komponente erstellt werden.

### 4.1 PostgreSQL-Secrets

```bash
vault kv put secret/data-platform/postgresql \
  root-password="pg-root-password-here" \
  airflow-password="airflow-db-password-here" \
  openmetadata-password="om-db-password-here" \
  superset-password="superset-db-password-here" \
  metabase-password="metabase-db-password-here" \
  keycloak-password="keycloak-db-password-here"
```

### 4.2 MinIO-Secrets

```bash
vault kv put secret/data-platform/minio \
  root-user="minioadmin" \
  root-password="secure-minio-password" \
  airflow-access-key="airflow-s3-key" \
  airflow-secret-key="airflow-s3-secret" \
  trino-access-key="trino-s3-key" \
  trino-secret-key="trino-s3-secret" \
  openmetadata-access-key="om-s3-key" \
  openmetadata-secret-key="om-s3-secret"
```

### 4.3 Airflow-Secrets

```bash
vault kv put secret/data-platform/airflow \
  fernet-key="$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')" \
  webserver-secret-key="$(openssl rand -base64 32)"
```

### 4.4 Superset-Secrets

```bash
vault kv put secret/data-platform/superset \
  secret-key="$(openssl rand -base64 32)"
```

### 4.5 Metabase-Secrets

```bash
vault kv put secret/data-platform/metabase \
  encryption-key="$(openssl rand -base64 32)"
```

### 4.6 Keycloak-Secrets

```bash
vault kv put secret/data-platform/keycloak \
  admin-password="keycloak-admin-password" \
  db-password="keycloak-db-password"
```

---

## Verifizierung

### ESO Status prüfen

```bash
# ESO sollte Secrets erfolgreich synchronisieren
kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=external-secrets -f

# ExternalSecret Ressourcen (ab TICKET-005)
kubectl get externalsecrets -n "$NAMESPACE"
kubectl describe externalsecret -n "$NAMESPACE" <name>
```

### Vault Status

```bash
# Vault Health Check
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- vault status

# Unseal Status sollte "false" sein (sealed = false = unsealed ✓)
```

---

## Backup & Recovery

### Vault Raft Snapshot erstellen

```bash
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- \
  vault operator raft snapshot save /tmp/vault-snapshot.snap

kubectl cp "$NAMESPACE/${RELEASE_NAME}-vault-0:/tmp/vault-snapshot.snap" ./vault-snapshot.snap
```

### Aus Snapshot wiederherstellen

```bash
# Snapshot hochladen
kubectl cp ./vault-snapshot.snap "$NAMESPACE/${RELEASE_NAME}-vault-0:/tmp/"

# Restore
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- \
  vault operator raft snapshot restore /tmp/vault-snapshot.snap
```

---

## Production Hardening (empfohlen)

1. **Vault Auto Unseal**: Statt manueller Unseal-Keys Cloud KMS verwenden
2. **Audit Logging**: Alle Vault-Operationen loggen (bereits in values/vault.yaml aktiviert)
3. **Sealed Secrets sicher verwahren**: Keys nicht im Git speichern
4. **Vault Admin Access kontrollieren**: Root Token nach Setup sperren (`vault token revoke`)
5. **Regular Backups**: Raft Snapshots regelmäßig erstellen und testen

---

## Troubleshooting

### Vault bleibt Sealed

```bash
# Status prüfen
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- vault status

# Falls sealed=true: weitere Keys nötig
# Falls sealed=false aber Probleme: Logs prüfen
kubectl logs -n "$NAMESPACE" "${RELEASE_NAME}-vault-0"
```

### ESO kann Vault nicht erreichen

```bash
# Vault erreichbar?
kubectl exec -n "$NAMESPACE" -l app.kubernetes.io/name=external-secrets -- \
  curl -v http://${RELEASE_NAME}-vault:8200/v1/sys/health

# ServiceAccount korrekt?
kubectl get sa -n "$NAMESPACE" external-secrets -o yaml
```

### TokenReview schlägt fehl

```bash
# RBAC-Binding prüfen
kubectl get clusterrolebinding | grep vault-tokenreview

# Vault Auth Method konfiguration
kubectl exec -n "$NAMESPACE" "${RELEASE_NAME}-vault-0" -- \
  vault read auth/kubernetes/config
```
