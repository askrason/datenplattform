# Konzept: Automatische k3s Cluster-Erstellung

---

## Übersicht

Ein Bash-Script, das:
1. k3s automatisch erstellt UND
2. Bestehende Cluster erkennt UND
3. Clustername flexibel akzeptiert

---

## Anforderungen

### Input-Optionen

```bash
# Option 1: Mit Clustername als Parameter
./scripts/create-cluster-k3s.sh my-cluster

# Option 2: Interaktiv erfragen
./scripts/create-cluster-k3s.sh
# → "Enter cluster name (or press Enter for default 'data-platform-dev'):"

# Option 3: Mit Flags
./scripts/create-cluster-k3s.sh --name my-cluster --ram 16GB
```

### Workflow

```
START
  ↓
1. Prüfe Voraussetzungen
   - kubectl installiert?
   - k3s installiert?
   - (optional) Docker installiert? (falls nötig)
   ↓
   Falls nicht → Installation anbieten
  ↓
2. Clustername prüfen
   - Parameter vorhanden?
   - Oder interaktiv erfragen
   - Standard: "data-platform-dev"
  ↓
3. Prüfe ob Cluster existiert
   - `kubectl cluster-info` ausführen
   - Falls Cluster läuft:
     * "Cluster 'XYZ' already running"
     * "Use --recreate to start fresh (WARNING: DATA LOSS)"
     * EXIT 0 (erfolgreich)
   - Falls Cluster existiert aber nicht läuft:
     * "Cluster exists but not running"
     * "Start with: k3s server"
     * EXIT 0
  ↓
4. k3s installieren/starten
   - curl -sfL https://get.k3s.io | sh -
   - Mit Konfiguration (RAM, CPUs, etc.)
  ↓
5. Warte bis Cluster bereit
   - kubectl get nodes → Ready?
   - Timeout: 5 Minuten
  ↓
6. Setze Namespace & Kontext
   - kubectl create namespace data-platform
   - kubectl config set-context --current --namespace=data-platform
  ↓
7. Installation überprüfen
   - kubectl cluster-info
   - kubectl get nodes
   - kubectl get namespaces
  ↓
SUCCESS ✓
```

---

## Implementierung

### Script-Name & Ort
- `scripts/create-cluster-k3s.sh`

### Komponenten

#### 1. Utility-Funktionen
```bash
log_info()      # ℹ Informationen
log_success()   # ✓ Erfolg
log_warning()   # ⚠ Warnung
log_error()     # ✗ Fehler
```

#### 2. Prüfungen
```bash
check_prerequisites()
  - kubectl vorhanden?
  - k3s vorhanden?
  
check_cluster_exists()
  - Cluster läuft?
  - Ist erreichbar?
  
get_cluster_name()
  - Aus Parameter $1
  - Oder interaktiv erfragen
```

#### 3. Cluster-Operationen
```bash
install_k3s()
  - curl -sfL https://get.k3s.io | sh -
  
wait_for_cluster()
  - Loop: kubectl get nodes bis "Ready"
  - Timeout: 5 min
  - Check alle 10 Sekunden
  
setup_namespace()
  - kubectl create namespace data-platform
  - kubectl config set-context
```

#### 4. Validierung
```bash
verify_installation()
  - kubectl cluster-info
  - kubectl get nodes
  - kubectl get namespaces
  - kubectl get pod --all-namespaces (Übersicht)
```

---

## Rückgabewerte

```
Exit Code 0 = Erfolg (neuer oder bestehender Cluster)
Exit Code 1 = Fehler (Voraussetzungen nicht erfüllt)
```

---

## Ausgabe-Beispiel

```
═══════════════════════════════════════════════
k3s Cluster Creation Script
═══════════════════════════════════════════════

ℹ Checking prerequisites...
  ✓ kubectl found: v1.32.0
  ✓ k3s found: v1.32.0

ℹ Cluster name: data-platform-dev (from parameter)

ℹ Checking if cluster exists...
  ✗ No cluster running yet

ℹ Installing k3s...
  → Running: curl -sfL https://get.k3s.io | sh -
  → Installation in progress...
  ✓ k3s installed successfully

ℹ Waiting for cluster to be ready...
  → Attempt 1/30: Cluster not ready yet
  → Attempt 2/30: Cluster not ready yet
  → Attempt 5/30: All nodes ready
  ✓ Cluster is ready

ℹ Setting up namespace...
  ✓ Namespace 'data-platform' created
  ✓ Context set to 'data-platform'

ℹ Verifying installation...
  ✓ Cluster Info:
    • Name: data-platform-dev
    • Kubernetes Version: v1.32.0
    • Nodes: 1 (Ready)
    • Namespaces: default, kube-system, data-platform

═══════════════════════════════════════════════
✓ k3s Cluster 'data-platform-dev' is ready!

Next steps:
  1. Deploy Data Platform:
     ./scripts/setup-k3s-dev.sh

  2. Access Cluster:
     kubectl get pods -n data-platform

  3. Port-forward:
     kubectl port-forward svc/ingress-nginx 80:80 -n ingress-nginx

═══════════════════════════════════════════════
```

---

## Edge Cases

### Fall 1: Cluster existiert bereits und läuft
```
✓ Cluster 'data-platform-dev' is already running
  No action taken.
  
  To recreate:
    ./scripts/create-cluster-k3s.sh data-platform-dev --recreate
```

### Fall 2: Cluster existiert aber läuft nicht
```
⚠ Cluster 'data-platform-dev' exists but is not running
  
  To start k3s:
    k3s server
```

### Fall 3: Clustername-Konflikt
```
⚠ Cluster name 'my-cluster' is already in use
  
  Choose a different name:
    ./scripts/create-cluster-k3s.sh other-name
```

### Fall 4: Keine Voraussetzungen
```
✗ kubectl not installed
  
  Install with:
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
```

---

## Sprachen

- ✅ Englisch (Standard)
- ✅ Deutsch (zusätzlich verfügbar über `--lang de`)

```bash
./scripts/create-cluster-k3s.sh --name mein-cluster --lang de
```

---

## Performance

- **Installation von Grund auf**: ~3-5 Minuten
- **Wenn k3s bereits existiert**: <1 Sekunde
- **Timeout für Cluster-Ready**: 5 Minuten (konfigurierbar)

---

## Nachgelagerte Schritte (NICHT im Script)

Diese werden NACH erfolgreichem Cluster-Setup gemacht:
1. `./scripts/setup-k3s-dev.sh` → Deployt die Data Platform
2. `./scripts/portforward-all.sh` → Öffnet Ports zu Services
3. Browser → http://localhost:8080 → Zugriff

---

## Dateien die angepasst werden

Nach Erstellung des Scripts:
- ✅ `docs/installation-de.md` → Link zu Script
- ✅ `docs/installation.md` → Link zu Script
- ✅ `README.md` → "Automatic Setup" Sektion
- ✅ `docs/quickstart-de.md` → Erweitern um cluster-creation

---

## Fragen zum Konzept

1. ✅ **Nur k3s?** Ja, andere später
2. ✅ **Prüfung ob läuft?** Ja, mit Details
3. ✅ **Clustername flexibel?** Ja, Parameter oder interaktiv
4. **Noch etwas hinzufügen?**
   - `--ram` Flag für WSL2 Memory?
   - `--recreate` Force-Neuinstallation?
   - Integration mit `setup-k3s-dev.sh`?

---

## Status

- [ ] Script schreiben
- [ ] Testen auf Linux
- [ ] Testen auf WSL2
- [ ] Dokumentation updaten
- [ ] In README verlinken
