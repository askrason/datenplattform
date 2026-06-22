# Offline & Air-Gapped Deployment-Anleitung

Strategien für das Deployment der Data Platform in Umgebungen mit eingeschränktem oder kein Internetzugriff.

---

## Überblick

Drei Ansätze, von einfachsten bis robustesten:

| Ansatz | Anwendungsfall | Komplexität | Netzwerk erforderlich |
|--------|--------|-----------|------------------|
| **Online Laden** | k3s hat Internet | Einfach | Ja (einmal) |
| **Image Export** | Transfer via USB/NFS | Mittel | Nein (nach Export) |
| **Registry Mirror** | Multi-System Deployments | Komplex | Nein (nach Setup) |

---

## Ansatz 1: Online Laden (Einfachster)

Benötigt Internetzugriff auf k3s/minikube Host, aber nur einmal.

### Schritte

```bash
# 1. Auf k3s Host mit Internet:
cd /path/to/datenplattform
./scripts/load-container-images.sh --target k3s

# 2. Verifiziere alle Images geladen:
k3s ctr images list | wc -l
# Sollte ~60+ Images zeigen

# 3. Deploye jetzt:
./scripts/switch-to-engineer.sh
```

**Zeit:** 10–30 Minuten (hängt von Bandbreite ab)
**Komplexität:** Niedrig
**Voraussetzungen:** Docker + k3s + Internet

---

## Ansatz 2: Export & Transfer (Mittel)

Pre-Lade Images auf System mit Internet, export zu TAR-Archiven, transfer zu Air-Gapped System.

### 2A: Export auf verbundenem System

```bash
# Auf Maschine A (mit Internet):
./scripts/export-images.sh --output ./images --compress

# Dies erstellt:
# images/vault-1.15.0.tar.gz
# images/postgresql-16.2.tar.gz
# images/minio-minio-latest.tar.gz
# ... (~30+ komprimierte Archive)
# images/load-exported-images.sh
```

**Größe:** ~500MB–2GB je nach Kompression

### 2B: Transfer-Archive

```bash
# Via USB-Stick, SCP, oder Netzwerk-Share:
scp -r images/ user@airgapped-system:/tmp/

# Oder:
rsync -av images/ user@airgapped-system:/tmp/
```

### 2C: Laden auf Air-Gapped System

```bash
# Auf Maschine B (kein Internet):
cd /tmp/images
./load-exported-images.sh k3s

# Verifiziere:
k3s ctr images list | wc -l
```

**Zeit:**
- Export: 15–20 Minuten
- Transfer: hängt von Netzwerk/USB-Geschwindigkeit ab
- Laden: 5–10 Minuten
- **Gesamt (Offline-Teil):** ~20 Minuten

**Komplexität:** Mittel

---

## Ansatz 3: Privates Registry Mirror (Erweitert)

Für mehrere k3s Cluster oder regelmäßige Updates. Benötigt privates Docker Registry.

### 3A: Registry einrichten

```bash
# Auf interner Maschine mit Internetzugriff:

# Option A: Docker Registry (einfachster)
docker run -d \
  -p 5000:5000 \
  --name registry \
  registry:2

# Option B: Harbor (mehr Features)
docker-compose up -d  # (via harbor docker-compose.yml)
```

### 3B: Images zur Registry synchronisieren

```bash
# Erstelle Sync-Skript (oder nutze skopeo/registry-sync)
./scripts/export-images.sh --output ./images

# Re-tag alle Images zu deiner Registry:
for image in $(docker images --format "{{.Repository}}:{{.Tag}}"); do
  docker tag "$image" "registry.internal:5000/$image"
  docker push "registry.internal:5000/$image"
done
```

### 3C: Update Helm Values

```yaml
# ci/values-offline.yaml
global:
  imageRegistry: "registry.internal:5000"
```

### 3D: Deploy aus Registry

```bash
helm install data-platform . \
  --values values.yaml \
  --values ci/values-offline.yaml
```

**Komplexität:** Hoch
**Vorteil:** Nahtlose Updates, mehrere Cluster, Versionierung

---

## Empfohlen: Hybrid-Ansatz

Für die meisten Organisationen:

```
1. Nutze Ansatz 1 (Online Laden) für Initial-Deployment
   → k3s Host lädt Images einmal
   → Schnell, einfach, niedriger Overhead

2. Wenn auf mehrere Systeme skaliert:
   → Wechsel zu Ansatz 2 (Export & Transfer)
   → Pre-Export einmal, über Deployments wiederverwenden
   → Dokumentiere Prozess in Ops Runbook

3. Für Produktion mit häufigen Updates:
   → Implementiere Ansatz 3 (Privates Registry)
   → Rechtfertigt Infrastruktur-Investment für große Deployments
```

---

## Quick Reference-Skripte

### Online laden

```bash
./scripts/load-container-images.sh --target k3s
```

### Alle Images exportieren

```bash
./scripts/export-images.sh --output ./images --compress
```

### Export Subset (Nur Engineer Dev)

```bash
./scripts/export-images.sh \
  --output ./images-engineer \
  --values ci/values-engineer-dev.yaml \
  --compress
```

### Dry-Run (Vorschau)

```bash
./scripts/export-images.sh --output ./images --dry-run
```

### Geladene Images auflisten

```bash
k3s ctr images list
```

---

## Netzwerk-Topologie

### Online Laden
```
┌─────────────────┐
│   k3s Host      │
│                 │
│ ┌─────────────┐ │
│ │   Docker    │ │──→ Docker Hub / Registries
│ │   daemon    │ │    (Images pullen)
│ └─────────────┘ │
│                 │
│ ┌─────────────┐ │
│ │   k3s       │ │
│ │   cluster   │ │
│ └─────────────┘ │
└─────────────────┘
```

### Export & Transfer
```
┌──────────────┐           ┌──────────────────────┐
│ Maschine A   │           │ Maschine B (Offline) │
│ (Internet)   │           │                      │
│              │──USB──→   │ ┌──────────────────┐ │
│ ┌──────────┐ │   Stick   │ │      k3s         │ │
│ │ Docker   │ │ oder SCP  │ │      cluster     │ │
│ └──────────┘ │           │ └──────────────────┘ │
│              │           │                      │
│ Export .tar  │           │ Lade .tar-Dateien    │
│ Dateien      │           │                      │
└──────────────┘           └──────────────────────┘
```

### Privates Registry
```
┌────────────────────────────────────────────────────┐
│ Internes Netzwerk                                  │
│                                                    │
│  ┌──────────────┐      ┌──────────────────────┐  │
│  │ Registry     │◄─────│ Maschine A (Sync)    │  │
│  │ (intern)     │      │ - pullt von Docker   │  │
│  │              │      │ - pusht zu registry  │  │
│  └──────────────┘      └──────────────────────┘  │
│         ▲                                          │
│         │                                          │
│         │ (pull)                                   │
│         │                                          │
│  ┌──────────────┐      ┌──────────────────────┐  │
│  │ k3s Cluster1 │      │ k3s Cluster2         │  │
│  │              │      │                      │  │
│  └──────────────┘      └──────────────────────┘  │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## Fehlerbehebung

### Export schlägt fehl: "docker: command not found"

```bash
# Stelle sicher Docker läuft
docker ps

# Falls nicht installiert:
# macOS: brew install docker
# Linux: sudo apt-get install docker.io
# Windows: Installiere Docker Desktop
```

### Laden schlägt fehl: "k3s: command not found"

```bash
# k3s muss installiert sein
which k3s

# Falls nicht:
curl -sfL https://get.k3s.io | sh -
```

### TAR-Dateien sind sehr groß

```bash
# Nutze Kompression (empfohlen)
./scripts/export-images.sh --compress

# Oder manuell:
tar czf images.tar.gz images/
```

### Transfer mit SCP ist langsam

```bash
# Komprimiere das Verzeichnis zuerst
tar czf images.tar.gz images/

# Dann transfer (viel schneller)
scp images.tar.gz user@target:/tmp/

# Auf Target:
tar xzf /tmp/images.tar.gz
cd images && ./load-exported-images.sh k3s
```

### Einige Images nicht lokal gefunden

```bash
# Dry-Run um zu sehen, was gepullt würde
./scripts/export-images.sh --dry-run

# Das ist normal — Export exportiert nur, was existiert.
# Nutze load-container-images.sh zuerst, um zu pullen:
./scripts/load-container-images.sh --target k3s --dry-run
./scripts/load-container-images.sh --target k3s  # Images pullen

# Dann exportieren
./scripts/export-images.sh --compress
```

---

## Sicherheitsaspekte

### Image-Integrität

**Risiko:** Verfälschte Images beim Transfer

**Mitigation:**
```bash
# Speichere Image-Digests vor Export
k3s ctr images list | grep sha256 > image-digests.txt

# Auf Target, verifiziere Digests passen:
k3s ctr images list | grep sha256
```

### Authentifizierung privates Registry

**Risiko:** Unbefugter Zugriff zu interner Registry

**Mitigation:**
```bash
# Nutze Basic Auth oder TLS
docker run -d \
  -p 5000:5000 \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -v /etc/registry/htpasswd:/auth/htpasswd:ro \
  registry:2
```

### Netzwerk-Isolation

**Risiko:** Images aus kompromittierten Netzwerken

**Best Practice:**
```bash
# Transferiere Images nur zwischen Netzwerken, die du kontrollierst
# Verifiziere Source und Destination
sha256sum images.tar.gz  # Überprüfe Checksumme
# Transfer
sha256sum images.tar.gz  # Verifiziere passt
```

---

## Siehe auch

- **Image-Laden**: `docs/image-management.md`
- **k3s Setup**: `docs/k3s-dev-setup.md`
- **Umgebungs-Umschalten**: `docs/environment-switching.md`
- **Operationsmanual**: `docs/operations.md`
