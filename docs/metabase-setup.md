# Metabase Setup & Konfiguration

## Überblick

Nach dem Deployment von Metabase (TICKET-009) mit oauth2-proxy SSO müssen folgende manuelle Schritte durchgeführt werden:

1. **Initial-Setup** (einmaliger Admin-Account)
2. **Trino-Datenquelle konfigurieren**
3. **Benutzer-Rollen verwalten**

---

## 1. Initial-Setup (Admin-Account)

### Zugriff auf Metabase

```
https://metabase.{{ your-domain }}/
```

Bei der ersten Anmeldung wird automatisch ein **initiales Admin-Setup** durchgeführt:

1. **Keycloak-Login**
   - Redirect zu Keycloak-Login-Seite
   - Keycloak-Credentials eingeben
   - oauth2-proxy leitet authentifizierten Request an Metabase weiter

2. **Metabase Initial-Setup**
   - Seite: "Let's set up Metabase" wird angezeigt
   - Admin-Account-Daten eintragen (mit Keycloak-Email)
   - Datenbankverbindung (bereits PostgreSQL `metabase` DB konfiguriert)
   - Fertig!

### Troubleshooting Initial-Setup

| Problem | Lösung |
|---------|--------|
| Redirect-Loop zu Keycloak | oauth2-proxy Service läuft nicht. `kubectl get pods` prüfen |
| "Cannot connect to database" | PostgreSQL-Service nicht erreichbar. `kubectl logs <metabase-pod>` prüfen |
| Blank Page nach Login | Metabase-Pod lädt. Kurz warten und neuladen. |

---

## 2. Trino-Datenquelle Konfigurieren

Nachdem der Admin-Account erstellt wurde:

### Schritte

1. **Admin-Panel öffnen**
   ```
   Klick auf Zahnrad-Icon oben rechts → "Admin settings"
   ```

2. **Database hinzufügen**
   ```
   Admin Panel → Databases → "Add database"
   ```

3. **Trino auswählen**
   - Database Type: `Trino`
   - Name: `Trino (Data Platform)`
   - Host: `{{ .Release.Name }}-trino`
   - Port: `8080`
   - Datenbank: `iceberg` (empfohlen) oder `minio` (Hive)
   - Username: Leer oder Standard-User
   - Passwort: Leer
   - Test connection

4. **Speichern**

### Kataloge

Metabase erkennt automatisch Catalogs/Schemas aus Trino:
- `iceberg` – für dbt-Outputs (strukturierte Tabellen)
- `minio` – für Raw-Daten (Hive-Metastore auf MinIO)
- `postgresql` – für operative Datenbanken (Airflow, OM)

---

## 3. Benutzer-Rollen Verwalten

### Benutzer hinzufügen

1. **Admin Panel → People → "Add new person"**

2. **Keycloak-Benutzer eingeben**
   - Email: Muss in Keycloak existieren
   - Password-Feld: Leer lassen (SSO über Keycloak)

3. **Rollen zuweisen**
   - `Admin` – Administratorzugriff
   - `Normal` – Voller Datenbankzugriff, kann Dashboards/Questions erstellen
   - `Metric Writer` – Kann nur spezifische Metriken erstellen
   - `Read-only` – Nur Dashboards ansehen

### Rollen-Mapping Keycloak ↔ Metabase

**Einschränkung:** Metabase kennt keine Keycloak-Gruppen → Rollen müssen manuell in Metabase zugewiesen werden.

**Zukünftige Lösung:** SCIM-Sync oder API-basierte Automation (Out of Scope für TICKET-009).

---

## 4. Datenquellen-Konfiguration via API (Optional)

Falls du Metabase automatisiert konfigurieren möchtest, nutze die Metabase REST API:

### Authentifizierung

```bash
# Login (erhält Session-Token)
curl -X POST http://metabase.example.com/api/session \
  -H "Content-Type: application/json" \
  -d '{"username":"admin@example.com","password":"..."}'
```

### Datenquelle hinzufügen

```bash
curl -X POST http://metabase.example.com/api/database \
  -H "X-Metabase-Session: <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Trino",
    "engine": "trino",
    "details": {
      "host": "{{ .Release.Name }}-trino",
      "port": 8080,
      "database": "iceberg"
    }
  }'
```

---

## 5. Dashboards & Questions

Nach der Datenquellen-Konfiguration können Nutzer:

1. **Questions** (adhoc Queries)
   ```
   + New → Question
   → Select Trino database
   → Visual Editor oder SQL
   ```

2. **Dashboards**
   ```
   + New → Dashboard
   → Questions hinzufügen
   ```

3. **Alerts** (optional)
   ```
   Dashboard → 3-Punkte-Menü → "Set up an alert"
   ```

---

## 6. Performance-Tipps

- **Caching aktivieren:** Admin Panel → Settings → Caching
- **Query Timeouts:** Trino-Queries können lange laufen. Metabase Timeout erhöhen: `1200s`
- **Row Limits:** Bei großen Tabellen: Admin → Database Settings → Query timeout

---

## 7. Backup & Migration

### Metabase-Daten sichern

```bash
# PostgreSQL Dump (Metabase-Datenbank)
kubectl exec -it <postgresql-pod> -- \
  pg_dump -U metabase -d metabase > metabase-backup.sql
```

### Wiederherstellen

```bash
kubectl exec -it <postgresql-pod> -- \
  psql -U metabase -d metabase < metabase-backup.sql
```

---

## 8. Troubleshooting-Checkliste

| Problem | Check |
|---------|-------|
| oauth2-proxy 502 Bad Gateway | Metabase Service läuft? `kubectl get svc metabase` |
| Trino-Connection fehlgeschlagen | Trino Service erreichbar? `curl http://trino:8080/ui/` |
| PostgreSQL-Connection fehlgeschlagen | PostgreSQL läuft? `kubectl get pods postgresql` |
| Slow Queries | Trino-Performance? Metabase Query Timeout erhöhen |

---

## Weitere Ressourcen

- Metabase Dokumentation: https://www.metabase.com/docs/
- oauth2-proxy Dokumentation: https://oauth2-proxy.github.io/
- Keycloak OIDC: https://www.keycloak.org/docs/latest/server_admin/
