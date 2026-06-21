# TICKET-010: Keycloak Sub-Chart + Realm-Konfiguration

## Ziel
Keycloak als zentralen Identity Provider (IdP) deployen. Alle Stack-Komponenten
(Airflow, Superset, OpenMetadata, MinIO, Metabase via oauth2-proxy) nutzen
Keycloak für SSO via OIDC. Der Realm wird als GitOps-fähige ConfigMap verwaltet.

## Voraussetzungen
- TICKET-001 bis TICKET-004 abgeschlossen
- CLAUDE.md gelesen (ADR-005, und Known Issue #6 zur Bitnami-Repo-Migration)

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-009
Neue Dateien: values/keycloak.yaml,
  templates/networkpolicies/keycloak-netpol.yaml,
  templates/externalsecrets/keycloak-secrets.yaml,
  files/keycloak-realm.json
```

## Zu erstellende / zu ändernde Dateien

### 1. `values/keycloak.yaml`

```yaml
keycloak:
  enabled: true

  auth:
    adminUser: admin
    existingSecret: keycloak-credentials
    existingSecretKey: admin-password

  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 1000
    fsGroup: 1000
  containerSecurityContext:
    <<: *defaultSecurityContext
    # AUSNAHME: Keycloak schreibt temporäre Provider-Dateien und Logs
    readOnlyRootFilesystem: false
  extraVolumes:
    - name: tmp
      emptyDir: {}
  extraVolumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: realm-config
      mountPath: /opt/bitnami/keycloak/data/import
      readOnly: true

  extraVolumesFromConfigMaps:
    - name: realm-config
      configMap:
        name: "{{ .Release.Name }}-keycloak-realm"

  resources:
    requests: { cpu: "500m", memory: "1Gi" }
    limits:   { cpu: "2000m", memory: "2Gi" }

  # Realm beim Start importieren
  extraStartupArgs: "--import-realm"

  # PostgreSQL als Keycloak-DB (kein eingebettetes H2)
  postgresql:
    enabled: false   # Wir nutzen das zentrale PostgreSQL aus TICKET-002
  externalDatabase:
    host: "{{ .Release.Name }}-postgresql"
    port: 5432
    database: keycloak
    user: keycloak
    existingSecret: keycloak-db-credentials
    existingSecretPasswordKey: password

  # HA: 2 Replicas mit Infinispan-Cluster
  replicaCount: 2
  cache:
    enabled: true
    stackName: kubernetes   # Infinispan Kubernetes Discovery

  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: "auth.{{ .Values.global.domain }}"
    tls: true
    selfSigned: false
    extraTls:
      - hosts: ["auth.{{ .Values.global.domain }}"]
        secretName: keycloak-tls
```

> Hinweis: Bitnami hat `charts.bitnami.com` im Aug. 2025 abgelöst – das Chart
> wird in diesem Projekt über `oci://registry-1.docker.io/bitnamicharts`
> bezogen (siehe `Chart.yaml`). Vor dem Deployment Version/Image-Tag prüfen
> (CLAUDE.md, Known Issue #6).

### 2. `files/keycloak-realm.json`

Realm-Export als JSON für GitOps-fähige Konfiguration.
Realm-Name: `data-platform`

Enthält folgende OIDC-Clients (vorkonfiguriert):

| Client-ID | App | Redirect URIs |
|---|---|---|
| `airflow` | Apache Airflow | `https://airflow.DOMAIN/oauth-authorized/keycloak` |
| `superset` | Apache Superset | `https://bi.DOMAIN/oauth-authorized/keycloak` |
| `openmetadata` | OpenMetadata | `https://catalog.DOMAIN/callback` |
| `metabase` | oauth2-proxy für Metabase | `https://metabase.DOMAIN/oauth2/callback` |
| `minio` | MinIO Console | `https://minio-console.DOMAIN/oauth_callback` |
| `trino` | Trino (optional, für zukünftige Auth) | `https://trino.DOMAIN/ui/oauth2/callback` |

Realm-Konfiguration enthält außerdem:
- **Gruppen:** `platform-admin`, `data-engineer`, `data-analyst`, `viewer`
- **Rollen:** pro Client (z.B. `airflow-admin`, `airflow-user`, `superset-admin`, `superset-analyst`)
- **Gruppen-Rollen-Mapping:** z.B. `platform-admin` → alle Admin-Rollen
- **Token-Konfiguration:** Access-Token TTL: 15min, Refresh-Token TTL: 8h
- **Password Policy:** Min. 12 Zeichen, 1 Großbuchstabe, 1 Sonderzeichen
- **Brute Force Protection:** aktiviert (5 Versuche, 5min Lockout)

**Wichtig:** Client-Secrets werden NICHT im Realm-JSON gespeichert.
Sie werden separat via Vault/ExternalSecret injiziert und in Keycloak
nach dem ersten Deployment gesetzt (dokumentiert in docs/keycloak-setup.md).

Erstelle das JSON als Platzhalter-Template mit `REPLACE_ME`-Markierungen
für Client-Secrets und Domain.

### 3. `templates/keycloak-realm-configmap.yaml`

ConfigMap die `files/keycloak-realm.json` als Volume in den Keycloak-Pod mounted:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-keycloak-realm
data:
  realm.json: |
    {{ .Files.Get "files/keycloak-realm.json" | indent 4 }}
```

### 4. `templates/networkpolicies/keycloak-netpol.yaml`

**Ingress:**
- Port 8080 vom Ingress Controller (UI + OIDC-Endpoints)
- Port 8080 von ALLEN Stack-Pods (OIDC Token Validation)
- Port 7800 von Keycloak-Pods untereinander (Infinispan-Cluster-Discovery)

**Egress:**
- PostgreSQL Port 5432 (Keycloak-DB)
- DNS Port 53
- Keycloak-intern Port 7800 (Infinispan)

### 5. `templates/externalsecrets/keycloak-secrets.yaml`

Liest aus Vault:
- `secret/data-platform/keycloak/admin-password` → `keycloak-credentials.admin-password`
- `secret/data-platform/postgresql/keycloak-password` → `keycloak-db-credentials.password`

### 6. `docs/keycloak-setup.md`

Manuelle Schritte nach erstem Deployment:
1. Admin-Login in Keycloak-UI
2. Realm `data-platform` prüfen (sollte automatisch importiert sein)
3. Client-Secrets generieren und in Vault eintragen
4. Ersten Admin-User anlegen und Gruppe `platform-admin` zuweisen
5. SMTP-Konfiguration für Password-Reset-Mails

## Akzeptanzkriterien

- [ ] Keycloak deployed (2 Replicas, Infinispan-Cluster)
- [ ] PostgreSQL als Keycloak-DB (kein H2) – Datenbank `keycloak` existiert (TICKET-002)
- [ ] Realm `data-platform` nach Deployment automatisch importiert
- [ ] Alle 6 OIDC-Clients im Realm vorkonfiguriert
- [ ] Gruppen + Rollen-Mapping vorhanden
- [ ] Brute-Force-Protection aktiviert
- [ ] Password-Policy konfiguriert
- [ ] NetworkPolicy: alle Stack-Pods können Port 8080 für OIDC erreichen
- [ ] Client-Secrets NICHT im Realm-JSON (nur via Vault)
- [ ] `docs/keycloak-setup.md` vorhanden
- [ ] Keycloak-UI via Ingress erreichbar (`auth.DOMAIN`)
- [ ] Bitnami-OCI-Repo/Version verifiziert (CLAUDE.md, Known Issue #6)
