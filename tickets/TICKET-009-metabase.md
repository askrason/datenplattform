# TICKET-009: Metabase Sub-Chart + oauth2-proxy (Keycloak SSO)

## Ziel
Metabase als ergänzendes Self-Service BI-Tool deployen. Da Metabase OSS kein
natives OIDC unterstützt, wird SSO via oauth2-proxy als Sidecar realisiert.
Trino als Haupt-Datenquelle.

## Voraussetzungen
- TICKET-001 bis TICKET-004 abgeschlossen
- TICKET-006 (Trino) abgeschlossen
- TICKET-010 (Keycloak) abgeschlossen oder zumindest Keycloak-Client-Secret bekannt
- CLAUDE.md gelesen (ADR-004: Metabase OSS → oauth2-proxy für SSO)

## Kontext-Session
```
Abgeschlossene Tickets: TICKET-001 bis TICKET-008
Neue Dateien: values/metabase.yaml,
  templates/networkpolicies/metabase-netpol.yaml,
  templates/externalsecrets/metabase-secrets.yaml
```

## Architektur-Hinweis (ADR-004)

```
Nutzer → Ingress → oauth2-proxy (Port 4180)
                       ↓ OIDC/Keycloak (authentifiziert)
                   Metabase (Port 3000, intern)
```

oauth2-proxy übernimmt Authentifizierung. Nach erfolgreichem OIDC-Login
wird der Request an Metabase weitergeleitet. Metabase selbst hat keinen
eigenen Login (oder wird mit einem technischen Admin-Account konfiguriert).

**Einschränkung:** Metabase kennt keine Keycloak-Gruppen → Rollen-Management
erfolgt manuell in Metabase oder via periodischem SCIM-Sync (Out of Scope).

## Zu erstellende / zu ändernde Dateien

### 1. `values/metabase.yaml`

Metabase Community Chart (Repository vor diesem Ticket in `Chart.yaml`
final verifizieren – aktuell als TODO markiert):

```yaml
metabase:
  enabled: true

  podSecurityContext:
    <<: *defaultPodSecurityContext
    runAsUser: 2000
    fsGroup: 2000
  securityContext:
    <<: *defaultSecurityContext
    # AUSNAHME: Metabase schreibt temporäre Dateien und H2-Fallback-DB
    readOnlyRootFilesystem: false
  extraVolumes:
    - name: tmp
      emptyDir: {}
  extraVolumeMounts:
    - name: tmp
      mountPath: /tmp

  resources:
    requests: { cpu: "500m", memory: "1Gi" }
    limits:   { cpu: "2000m", memory: "4Gi" }

  # PostgreSQL als App-DB (nicht H2!)
  database:
    type: postgres
    host: "{{ .Release.Name }}-postgresql"
    port: 5432
    dbname: metabase
    existingSecret: metabase-db-credentials
    existingSecretUsernameKey: username
    existingSecretPasswordKey: password

  # Service intern (oauth2-proxy ist vorgelagert)
  service:
    type: ClusterIP
    port: 3000

  # Kein direktes Ingress auf Metabase – läuft hinter oauth2-proxy
  ingress:
    enabled: false

  # Encryption Key für Metabase-interne Datenverschlüsselung
  extraEnv:
    - name: MB_ENCRYPTION_SECRET_KEY
      valueFrom:
        secretKeyRef:
          name: metabase-credentials
          key: encryption-key

  # Trino-Verbindung (wird nach Deployment manuell in MB UI konfiguriert
  # oder via Metabase API/Init-Container gesetzt)
  # Dokumentiert in docs/metabase-setup.md
```

**oauth2-proxy als zusätzlicher Deployment (eigenes Template):**

Erstelle `templates/metabase-oauth2-proxy.yaml`:

```yaml
# Separates Deployment für oauth2-proxy vor Metabase
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-metabase-oauth2-proxy
spec:
  replicas: 1
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 2000
        fsGroup: 2000
      containers:
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.7.0
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
            seccompProfile:
              type: RuntimeDefault
          args:
            - --provider=oidc
            - --oidc-issuer-url=https://{{ keycloak-url }}/realms/data-platform
            - --client-id=metabase
            - --upstream=http://{{ .Release.Name }}-metabase:3000
            - --http-address=0.0.0.0:4180
            - --email-domain=*
            - --cookie-secure=true
            - --cookie-samesite=lax
            - --skip-provider-button=true
          env:
            - name: OAUTH2_PROXY_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: metabase-oidc-credentials
                  key: client-secret
            - name: OAUTH2_PROXY_COOKIE_SECRET
              valueFrom:
                secretKeyRef:
                  name: metabase-oidc-credentials
                  key: cookie-secret
          resources:
            requests: { cpu: "50m", memory: "64Mi" }
            limits:   { cpu: "200m", memory: "128Mi" }
          ports:
            - containerPort: 4180
```

**Ingress zeigt auf oauth2-proxy (Port 4180), nicht auf Metabase:**

```yaml
# templates/metabase-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-metabase
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
    - host: "metabase.{{ .Values.global.domain }}"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .Release.Name }}-metabase-oauth2-proxy
                port:
                  number: 4180
  tls:
    - secretName: metabase-tls
      hosts: ["metabase.{{ .Values.global.domain }}"]
```

### 2. `templates/networkpolicies/metabase-netpol.yaml`

**oauth2-proxy – Ingress:**
- Port 4180 vom Ingress Controller

**oauth2-proxy – Egress:**
- Metabase Port 3000 (upstream)
- Keycloak Port 8080/8443 (OIDC)
- DNS Port 53

**Metabase – Ingress:**
- Port 3000 NUR von oauth2-proxy (kein direkter Ingress-Zugriff)

**Metabase – Egress:**
- Trino Port 8080 (Queries)
- PostgreSQL Port 5432 (App-DB)
- DNS Port 53

### 3. `templates/externalsecrets/metabase-secrets.yaml`

Liest aus Vault:
- `secret/data-platform/postgresql/metabase-password` → `metabase-db-credentials.password`
- `secret/data-platform/metabase/encryption-key` → `metabase-credentials.encryption-key`
- `secret/data-platform/metabase/keycloak-client-secret` → `metabase-oidc-credentials.client-secret`
- `secret/data-platform/metabase/cookie-secret` → `metabase-oidc-credentials.cookie-secret`

Cookie-Secret generieren: `openssl rand -base64 32 | tr -- '+/' '-_'`

### 4. `docs/metabase-setup.md`

Manuelle Schritte nach Deployment:
1. Metabase Initial-Setup via UI (einmaliger Admin-Account anlegen)
2. Trino als Datenbank-Verbindung hinzufügen
3. Metabase-User-Rollen konfigurieren
4. (Optional) Metabase API für automatische Datenquellen-Konfiguration

## Akzeptanzkriterien

- [ ] Metabase deployed mit PostgreSQL als App-DB (kein H2)
- [ ] oauth2-proxy deployed und als Ingress-Upstream konfiguriert
- [ ] SSO via Keycloak: Login ohne Metabase-eigenen Login-Screen
- [ ] Metabase Port 3000 NUR von oauth2-proxy erreichbar (nicht vom Ingress direkt)
- [ ] Alle Secrets via ExternalSecret (inkl. Cookie-Secret)
- [ ] oauth2-proxy: `readOnlyRootFilesystem: true` (schreibt nichts)
- [ ] Metabase: `readOnlyRootFilesystem: false` mit Kommentar
- [ ] `docs/metabase-setup.md` vorhanden
