# Data Engineer Entwicklungsumgebungs-Setup

## Überblick

Schnelle lokale Entwicklungsumgebung für **DAG/dbt-Entwicklung**.

- **Komponenten:** Airflow, Trino, PostgreSQL, MinIO
- **NICHT enthalten:** Vault, Keycloak, OpenMetadata (Sicherheit nicht relevant für DAG-Entwicklung)
- **Ressourcen:** 4-6 GB RAM
- **Setup-Zeit:** 3-4 Minuten

## Schnellstart

```bash
cd datenplattform
chmod +x scripts/setup-engineer-dev.sh
./scripts/setup-engineer-dev.sh
```

## Was ist enthalten

| Komponente | Zweck | Anmerkungen |
|-----------|-------|-----------|
| **Airflow** | DAG-Orchestrierung + Planung | Fokus dieser Umgebung |
| **Trino** | Query-Engine zum Testen von Queries | Minimales 1-Worker-Setup |
| **PostgreSQL** | Data Warehouse + Airflow Metastore | Einzelne Replica |
| **MinIO** | S3-kompatibler Object Store für DAG-Artefakte | Standalone-Modus |

## Zugriff auf Services

### Airflow Webserver

```bash
kubectl port-forward svc/data-platform-airflow-webserver 8080:8080
# Dann: http://localhost:8080
```

**Login:** airflow / airflow (Standard)

### Trino UI

```bash
kubectl port-forward svc/data-platform-trino 8080:8080
# Dann: http://localhost:8080/ui/
```

## Häufige Aufgaben

### DAG erstellen/deployen

```bash
# Finde Airflow-Scheduler-Pod
kubectl get pods | grep airflow-scheduler

# Kopiere DAG-Datei
kubectl cp my_dag.py <pod-name>:/opt/airflow/dags/

# Oder nutze Volume-Mount, falls dags-pvc existiert
kubectl get pvc | grep airflow
```

### Query in Trino testen

```bash
kubectl port-forward svc/data-platform-trino 8080:8080

# Dann besuche http://localhost:8080/ui/
# Oder nutze trino CLI:
trino --server http://localhost:8080 --catalog minio --schema default
```

### PostgreSQL überprüfen

```bash
kubectl exec -it data-platform-postgresql-0 -- psql -U postgres -d airflow
```

### MinIO anzeigen

```bash
kubectl port-forward svc/data-platform-minio 9001:9001
# Konsole: http://localhost:9001 (Anmeldedaten aus env/logs)
```

## Überwachung

```bash
# Pod-Status
kubectl get pods -w

# Logs
kubectl logs <pod-name> -f

# Ressourcennutzung
kubectl top pods
```

## Cleanup

```bash
# Deployment entfernen
helm uninstall data-platform

# Persistente Daten entfernen
kubectl delete pvc --all
```

## Wichtige Hinweise

⚠️ **NICHT produktionsreif:**
- Kein Vault/Keycloak = keine Authentifizierung/Secrets-Management
- Kein OpenMetadata = keine Data Governance
- Einzelne Replicas = keine HA
- Für produktionsähnliche Tests verwende `values-k3s-dev.yaml`

✅ **Gut für:**
- DAG/dbt-Entwicklung und Tests
- Query-Entwicklung
- Lokale Iteration
- Testen von Airflow-Jobs vor Push

## Fehlerbehebung

### Pod startet nicht

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Speichermangel

WSL2-Speicher erhöhen:
```ini
# .wslconfig
[wsl2]
memory=8GB
```

### Helm Timeout

```bash
helm upgrade data-platform . \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --timeout 15m
```

## Siehe auch

- Full-Stack Dev: `docs/k3s-dev-setup.md`
- Analyst-Only Setup: `docs/analyst-dev-setup.md`
- Architektur: `docs/architecture.md`
