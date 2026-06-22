# Keycloak Setup & Konfiguration

## Überblick

Nach dem Deployment von Keycloak (TICKET-010) müssen folgende manuelle Schritte durchgeführt werden:

1. **Admin-Login in Keycloak-UI**
2. **Realm `data-platform` verifizieren** (sollte automatisch importiert sein)
3. **Client-Secrets generieren und in Vault eintragen**
4. **Ersten Admin-User anlegen und Gruppen zuweisen**
5. **(Optional) SMTP-Konfiguration für Password-Reset-Mails**

---

## 1. Admin-Login in Keycloak-UI

### Zugriff auf Keycloak-Admin

```
https://auth.{{ your-domain }}/admin/
```

### Credentials

- **Username:** `admin`
- **Passwort:** Aus Vault (`secret/data-platform/keycloak/admin-password`)

---

## 2. Realm `data-platform` Verifizieren

Nach dem Deployment sollte der Realm `data-platform` automatisch importiert sein (via `--import-realm` Flag und `files/keycloak-realm.json`).

### Überprüfung

1. **Admin-UI öffnen:** https://auth.{{ your-domain }}/admin/
2. **Realm auswählen:** Dropdown oben links → `data-platform`
3. **Prüfung:**
   - Realm sollte vorhanden sein
   - **Clients** sollten sichtbar sein:
     - `airflow`
     - `superset`
     - `openmetadata`
     - `metabase`
     - `minio`
     - `trino` (deaktiviert, optional)
   - **Groups** sollten vorhanden sein:
     - `platform-admin`
     - `data-engineer`
     - `data-analyst`
     - `viewer`

---

## 3. Client-Secrets Generieren und in Vault Eintragen

**Wichtig:** Client-Secrets sind NICHT im Realm-JSON enthalten (GitOps-Safe). Sie müssen nach dem Deployment manuell generiert und in Vault hinterlegt werden.

### Für jeden Client (airflow, superset, openmetadata, metabase, minio):

1. **Admin-UI → Clients → Client auswählen** (z.B. `airflow`)

2. **Tab "Credentials"**
   - Unter "Client Secret" auf "Regenerate" klicken
   - Secret kopieren

3. **In Vault eintragen**

   ```bash
   vault kv put secret/data-platform/keycloak/airflow-client-secret \
     secret="<GENERATED_SECRET>"
   ```

   **Vault-Pfade pro Client:**
   - `secret/data-platform/keycloak/airflow-client-secret`
   - `secret/data-platform/keycloak/superset-client-secret`
   - `secret/data-platform/keycloak/openmetadata-client-secret`
   - `secret/data-platform/keycloak/metabase-client-secret`
   - `secret/data-platform/keycloak/minio-client-secret`

4. **ExternalSecrets reconcilieren**
   - ExternalSecret-Pods warten kurz, bis Vault-Secrets synced sind
   - Überprüfung: `kubectl get externalSecrets`

### Redirect URIs Prüfen

In jedem Client: **Tab "Access"**
- Redirect URIs sollten automatisch aus dem Realm-JSON gesetzt sein
- Falls nicht, manuell hinzufügen:

| Client | Redirect URI |
|--------|--------------|
| airflow | `https://airflow.{{ domain }}/oauth-authorized/keycloak` |
| superset | `https://bi.{{ domain }}/oauth-authorized/keycloak` |
| openmetadata | `https://catalog.{{ domain }}/callback` |
| metabase | `https://metabase.{{ domain }}/oauth2/callback` |
| minio | `https://minio-console.{{ domain }}/oauth_callback` |

---

## 4. Ersten Admin-User Anlegen und Gruppen Zuweisen

### Admin-User erstellen

1. **Admin-UI → Users → "Create new user"**

2. **Userdetails:**
   - Username: `admin`
   - Email: `admin@{{ domain }}`
   - First Name: `Admin`
   - Last Name: `User`
   - Email Verified: ✓
   - Enabled: ✓

3. **Tab "Credentials"**
   - Password setzen (mindestens 12 Zeichen, 1 Großbuchstabe, 1 Sonderzeichen)
   - "Temporary" deaktivieren (damit kein Password-Change beim nächsten Login erzwungen wird)

4. **Tab "Groups"**
   - `platform-admin` hinzufügen
   - `platform-admin` Gruppe sollte automatisch alle Admin-Rollen zuweisen

5. **Speichern**

### Admin-Rollen verifizieren

1. **Admin-UI → Realm Roles / Client Roles prüfen**
   - `platform-admin` Gruppe sollte folgende Rollen haben:
     - `airflow-admin` (Client: airflow)
     - `superset-admin` (Client: superset)
     - `admin` (Client: openmetadata)
     - `admin` (Client: metabase)
     - `console-admin` (Client: minio)

---

## 5. (Optional) SMTP-Konfiguration für Password-Reset-Mails

Damit Nutzer selbst ihr Passwort zurücksetzen können:

1. **Admin-UI → Realm Settings → Email**

2. **SMTP-Server konfigurieren:**
   - Host: `smtp.{{ your-mail-server }}`
   - Port: `587` (TLS) oder `465` (SSL)
   - From: `noreply@{{ domain }}`
   - From Display Name: `Data Platform`
   - Credentials: Username + Passwort (falls erforderlich)

3. **Test-Mail versenden**
   - "Test connection" klicken
   - Bestätigung prüfen

---

## 6. Benutzer-Verwaltung

### Neue Benutzer hinzufügen

1. **Admin-UI → Users → "Create new user"**

2. **Detailinformationen:**
   - Username, Email, First/Last Name eingeben
   - "Email Verified" ✓
   - "Enabled" ✓

3. **Passwort setzen (Tab "Credentials")**

4. **Gruppen zuweisen (Tab "Groups")**
   - Je nach Rolle: `data-engineer`, `data-analyst`, oder `viewer`

5. **Speichern**

### Gruppenzuweisung & Automatische Rollen

Sobald ein Nutzer einer Gruppe zugewiesen wird, erhält er automatisch alle Client-Rollen der Gruppe:

| Gruppe | Zugewiesene Client-Rollen |
|--------|--------------------------|
| `platform-admin` | Alle Admin-Rollen |
| `data-engineer` | `airflow-user`, `superset-analyst`, `openmetadata.data-consumer`, `metabase.normal` |
| `data-analyst` | `superset-viewer`, `openmetadata.data-consumer`, `metabase.normal` |
| `viewer` | `superset-viewer`, `openmetadata.data-consumer`, `metabase.read-only` |

---

## 7. Token-Verhalten Überprüfen

Die Realm-Konfiguration setzt folgende Token-Zeiten:

```
Access Token TTL: 15 Minuten
Refresh Token TTL: 8 Stunden
```

Diese Werte können in der Realm-JSON angepasst werden und werden beim nächsten Import überschrieben. Zum Ändern **nach Deployment**:

1. **Admin-UI → Realm Settings → Tokens**
2. Access Token Lifespan, Refresh Token Lifespan anpassen
3. Speichern

---

## 8. Sicherheitsrichtlinien (Realm-Konfiguriert)

Folgende Sicherheitsmaßnahmen sind bereits im Realm konfiguriert:

- **Password Policy:** Mindestens 12 Zeichen, 1 Großbuchstabe, 1 Sonderzeichen
- **Brute Force Protection:** Aktiviert (5 Failed Logins → 5 min Lockout)
- **Remember Me:** Aktiviert
- **User Registration:** Aktiviert (neue Nutzer können selbst registrieren)
- **Duplicate Emails:** Deaktiviert (Emails müssen eindeutig sein)

---

## 9. Troubleshooting

| Problem | Lösung |
|---------|--------|
| Cannot login to admin | Keycloak-Pod läuft nicht. `kubectl get pods keycloak` prüfen |
| Realm `data-platform` fehlt | ConfigMap nicht gemountet. `kubectl exec -it <keycloak-pod> -- ls /opt/bitnami/keycloak/data/import/` |
| Client-Secret für App ungültig | In Vault überprüfen: `vault kv get secret/data-platform/keycloak/XXX-client-secret` |
| OIDC-Login fehlgeschlagen | Redirect URIs in Keycloak-Admin prüfen. Client-Secret in Vault korrekt? |
| Infinispan-Clustering funktioniert nicht | Keycloak-Pods können sich gegenseitig nicht erreichen. NetworkPolicy prüfen (Port 7800) |

---

## 10. Backup & Disaster Recovery

### Realm-Export

```bash
# Export über Admin-REST-API
curl -X GET \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  https://auth.{{ domain }}/admin/realms/data-platform > realm-backup.json
```

### Realm-Restore

1. **Neue Realm-JSON in `files/keycloak-realm.json` ersetzen**
2. **ConfigMap updaten:** `kubectl apply -f templates/keycloak-realm-configmap.yaml`
3. **Keycloak-Pod neustarten:** `kubectl rollout restart deployment keycloak`
4. **Realm wird automatisch re-imported**

---

## Weitere Ressourcen

- Keycloak Dokumentation: https://www.keycloak.org/documentation.html
- OIDC-Standards: https://openid.net/specs/openid-connect-core-1_0.html
- Keycloak Admin REST API: https://www.keycloak.org/docs-api/latest/rest-api/
