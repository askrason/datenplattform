# Container-Image-Verwaltung

Vorladung von Container-Images für Air-Gapped oder eingeschränkte Umgebungen.

---

## Das Problem

Beim Deployment auf einem System mit eingeschränktem Internetzugriff (oder kein Internet):
- k3s/minikube können Images nicht on-demand pullen
- Deployment schlägt mit `ImagePullBackOff` fehl
- Manuelle Image-Verwaltung ist mühsam

## Die Lösung

**`scripts/load-container-images.sh`** automatisiert:
1. Alle Image-Namen aus dem Helm Chart extrahieren
2. Überprüfen, welche lokal existieren
3. Fehlende pullen
4. Sie in k3s/minikube laden

---

## Schnellstart

### Full-Stack Setup

```bash
# 1. Auf Maschine MIT Internetzugriff:
./scripts/load-container-images.sh --target k3s

# ODER für minikube:
./scripts/load-container-images.sh --target minikube
```

### Sehen, was passieren würde (Keine Änderungen)

```bash
./scripts/load-container-images.sh --target k3s --dry-run
```

### Benutzerdefinierte Values (Rollenspezifisch)

```bash
# Laden Sie Images nur für Engineer Dev
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-engineer-dev.yaml

# Laden Sie Images für Analyst Dev
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-analyst-dev.yaml
```

---

## Was es tut

### Schritt 1: Images extrahieren

```bash
helm template data-platform . | grep image:
```

Findet alle Container-Image-Referenzen im templatisierten Chart. Beispiele:
```
vault:1.15.0
postgresql:16.2
minio/minio:latest
apache/airflow:2.8.0
# ... und 50+ mehr
```

### Schritt 2: Lokale Images überprüfen

```bash
docker image inspect vault:1.15.0  # existiert?
```

**Schnell** — nutzt nur lokalen Docker Daemon.

### Schritt 3: Fehlende pullen

```bash
docker pull vault:1.15.0
docker pull postgresql:16.2
# ... alle fehlenden Images
```

Pulled nur, was nicht bereits lokal ist.

### Schritt 4: In Runtime laden

**Für k3s:**
```bash
docker save vault:1.15.0 | k3s ctr images import /dev/stdin
```

**Für minikube:**
```bash
minikube image load vault:1.15.0
```

---

## Typische Workflows

### Szenario 1: Offline vorbereiten

Maschine A (mit Internet) → Maschine B (Air-Gapped k3s)

```bash
# Auf Maschine A:
./scripts/load-container-images.sh --target k3s

# Verifiziere alle Images geladen:
k3s ctr images list

# Überprüfe: alle 60+ Images sind da
```

### Szenario 2: Rollenspezifisches Laden

```bash
# Engineer braucht nur Airflow + Trino + PostgreSQL + MinIO
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-engineer-dev.yaml

# Analyst braucht nur Trino + Superset + Metabase + PostgreSQL
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-analyst-dev.yaml
```

### Szenario 3: Inkrementelle Updates

Neue Version von Superset veröffentlicht:

```bash
# Update Chart.yaml → bump superset chart version
# Dann:
./scripts/load-container-images.sh --target k3s

# Skript pullt NUR die neue Version, nutzt existierende Images wieder
```

---

## Ausgabebeispiel

```
ℹ Konfiguration:
ℹ   Repository:  /home/user/datenplattform
ℹ   Target:      k3s
ℹ   Mode:        normal

ℹ Extrahiere Images aus Helm Chart...
ℹ Gefunden 62 Image(s) zum Verarbeiten

Verarbeite vault:1.15.0 ... existiert lokal
✓ Geladen zu k3s: vault:1.15.0

Verarbeite postgresql:16.2 ... nicht lokal gefunden
ℹ Pulling: postgresql:16.2
✓ Gepullt: postgresql:16.2
✓ Geladen zu k3s: postgresql:16.2

Verarbeite minio/minio:latest ... existiert lokal
✓ Geladen zu k3s: minio/minio:latest

...

ℹ Zusammenfassung:
ℹ   Gefundene Images:  62
ℹ   Gepullt:        15
ℹ   Geladen:        62
ℹ   Fehlgeschlagen:        0
```

---

## Befehlsreferenz

### Grundlegende Verwendung

```bash
./scripts/load-container-images.sh
# Standard: target=k3s, nutzt base values.yaml
```

### Mit minikube

```bash
./scripts/load-container-images.sh --target minikube
# Benötigt: minikube start
```

### Nur Docker (Keine k3s/minikube)

```bash
./scripts/load-container-images.sh --target docker
# Pulled nur Images, lädt nicht zu Runtime
```

### Dry Run (Vorschau)

```bash
./scripts/load-container-images.sh --dry-run
# Zeigt, was gepullt/geladen würde OHNE Änderungen
```

### Benutzerdefinierte Values

```bash
./scripts/load-container-images.sh \
  --values ci/values-engineer-dev.yaml

# ODER mehrere Overrides:
./scripts/load-container-images.sh \
  --values values.yaml \
  --values ci/values-engineer-dev.yaml \
  --values my-custom-overrides.yaml
```

### Optionen kombinieren

```bash
# Test-Lauf mit benutzerdefinierten Values vor echtem Laden
./scripts/load-container-images.sh \
  --target k3s \
  --values ci/values-analyst-dev.yaml \
  --dry-run
```

---

## Verifizierung

### Images in k3s überprüfen

```bash
# Alle geladenen Images auflisten
k3s ctr images list

# Zähle sie
k3s ctr images list | wc -l

# Suche nach spezifischem Image
k3s ctr images list | grep superset
```

### Images in minikube überprüfen

```bash
minikube image ls
```

### Images in Docker überprüfen

```bash
docker images | head -20
```

---

## Fehlerbehebung

### "docker pull" schlägt fehl

```bash
# Überprüfe, Docker Daemon läuft
docker ps

# Überprüfe, Docker kann Registries erreichen
docker pull hello-world

# Überprüfe Internet-Konnektivität
ping docker.io
```

### "k3s ctr" Befehl nicht gefunden

```bash
# k3s ist eine einzelne Binary, stelle sicher, es ist im PATH
which k3s

# Falls nicht installiert:
curl -sfL https://get.k3s.io | sh -
```

### minikube image load schlägt fehl

```bash
# Überprüfe minikube läuft
minikube status

# Falls gestoppt:
minikube start

# Überprüfe minikube hat genug Speicher
minikube df
```

### Image-Laden erfolgreich, aber Pod pullt immer noch aus Registry

K3s könnte immer noch pullen, wenn `imagePullPolicy: Always`. Chart nutzt `IfNotPresent`:

```yaml
# In values.yaml
imagePullPolicy: IfNotPresent  # Nutze lokales Image, falls verfügbar
```

Falls du trotzdem Pulls siehst, überprüfe:
```bash
kubectl describe pod <pod-name> | grep "Image:"
```

---

## Performance-Hinweise

**Erster Lauf:**
- 60+ Images ~500MB–2GB Download
- Zeit: 10–30 Minuten (hängt von Internet-Geschwindigkeit ab)

**Nachfolgende Läufe:**
- Skript überspringt existierende Images
- Nur neue/aktualisierte Images werden gepullt
- Zeit: 1–5 Minuten

**Netzwerk:**
- Pullt von offiziellen Registries (Docker Hub, Bitnami, etc.)
- Nutzt Standard-Anmeldedaten aus `~/.docker/config.json`, falls erforderlich

---

## Best Practices

### 1. Vorladung für Deployment-Tag

```bash
# Mache dies einen Tag vor oder am Morgen des Deployments
./scripts/load-container-images.sh --target k3s
```

### 2. Nutze Dry-Run zur Validierung

```bash
# Immer zuerst Vorschau
./scripts/load-container-images.sh --dry-run

# Dann echtes Laden
./scripts/load-container-images.sh
```

### 3. Passe Values an Deployment an

```bash
# Falls du mit engineer-dev.yaml deployst, lade damit:
./scripts/load-container-images.sh --values ci/values-engineer-dev.yaml
```

### 4. Dokumentiere geladene Versionen

```bash
# Speichere eine Liste für deine Unterlagen
k3s ctr images list > loaded-images-$(date +%Y-%m-%d).txt
```

### 5. Automatisiere für CI/CD

```bash
# In deinem Deploy-Skript:
./scripts/load-container-images.sh --target k3s && \
./scripts/switch-to-engineer.sh
```

---

## Siehe auch

- **Deployment-Anleitung**: `docs/k3s-dev-setup.md`
- **Umgebungs-Umschalten**: `docs/environment-switching.md`
- **Operationsmanual**: `docs/operations.md`
