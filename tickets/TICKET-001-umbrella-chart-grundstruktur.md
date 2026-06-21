# TICKET-001: Umbrella Chart Grundstruktur

## Ziel
Erstelle die Grundstruktur des Umbrella Helm Charts mit globalen Security-Defaults,
Dependency-Deklarationen und Validierungsschema. Dieses Ticket legt das Fundament
für alle nachfolgenden Tickets.

## Kontext
- Lies CLAUDE.md vollständig vor Beginn
- Orientierung: BundesMessenger Helm Chart Pattern (opencode.de)
- Alle nachfolgenden Tickets bauen auf dieser Struktur auf

## Status (Stand dieser Überarbeitung)
`Chart.yaml`, `values.yaml` und `struktur.txt` wurden bereits vorab vervollständigt
(siehe Changelog in README.md): alle 10 Dependencies (inkl. vault, external-secrets,
keycloak, metabase) sind in `Chart.yaml` deklariert, der `global`-Block existiert in
`values.yaml`. Für dieses Ticket bleiben noch offen: `values.schema.yaml`,
`templates/_helpers.tpl`, `templates/networkpolicies/default-deny.yaml`,
`.helmignore`, `scripts/validate.sh`, `scripts/generate-schema.sh`.

## Zu erstellende Dateien

### 1. `Chart.yaml`
Bereits vorhanden (siehe oben) – bei Bedarf nur die Bitnami-Versionspins für
`postgresql`/`keycloak` final setzen (siehe CLAUDE.md Known Issue #6) und das
`metabase`-Repository verifizieren (aktuell als TODO markiert).

### 2. `values.yaml`
Bereits vorhanden. Enthält:
- YAML-Anchors für globale Security-Defaults (`&defaultSecurityContext`, `&defaultPodSecurityContext`)
- `global`-Block: domain, storageClass, imageRegistry, imagePullPolicy, imagePullSecrets, namespaceSuffix
- Für jede Komponente: `enabled: true/false` Flag + minimale Defaults
- Alle Passwörter/Keys referenzieren `existingSecret` (NIE Klartext)
- Inline-Kommentare auf Deutsch für jede Sektion

Security-Anchors (ganz oben, vor allen Komponenten):
```yaml
x-security-context: &defaultSecurityContext
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault

x-pod-security: &defaultPodSecurityContext
  runAsNonRoot: true
  fsGroupChangePolicy: OnRootMismatch
```

### 3. `values.schema.yaml`
Definiert für jede Komponente:
- `enabled` (boolean, required)
- Mindest-Ressourcen-Validierung (cpu/memory nicht leer)
- `existingSecret` Pflichtfeld wenn keine Default-Werte

### 4. `templates/_helpers.tpl`
Enthält folgende Template-Funktionen:
- `data-platform.name` – Chart-Name
- `data-platform.fullname` – Release + Chart-Name
- `data-platform.labels` – Standard-Labels (app, version, managed-by)
- `data-platform.selectorLabels` – Selector-Labels
- `data-platform.securityContext` – gibt defaultSecurityContext zurück
- `data-platform.podSecurityContext` – gibt defaultPodSecurityContext zurück
- `data-platform.resources` – Validiert dass requests + limits gesetzt sind

### 5. `templates/networkpolicies/default-deny.yaml`
Deny-all-ingress und Deny-all-egress NetworkPolicy für den gesamten Namespace.
Wird von allen anderen NetworkPolicy-Templates als Basis vorausgesetzt.

```yaml
# Ingress: Deny all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
# Egress: Deny all (außer DNS)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### 6. `.helmignore`
Standard-Helm-Ignore + `*.md`, `docs/`, `scripts/`, `ci/`

### 7. `scripts/validate.sh`
```bash
#!/bin/bash
set -euo pipefail
echo "→ Dependency Update..."
helm dependency update
echo "→ Lint..."
helm lint . --values values.yaml
echo "→ Template Dry-Run..."
helm template data-platform . --values values.yaml \
  | kubectl apply --dry-run=client -f -
echo "✓ Validierung erfolgreich"
```

### 8. `scripts/generate-schema.sh`
Konvertiert `values.schema.yaml` → `values.schema.json` via Python/yq.

### 9. `README.md`
Bereits vorhanden – bei Bedarf um projektspezifische Hinweise ergänzen.

## Akzeptanzkriterien

- [ ] `helm dependency update` läuft ohne Fehler
- [ ] `helm lint . --values values.yaml` gibt keine Errors oder Warnings
- [ ] `helm template . --values values.yaml` produziert valides YAML
- [ ] YAML-Anchors funktionieren (via `helm template` überprüfbar)
- [ ] `templates/networkpolicies/default-deny.yaml` ist vorhanden
- [ ] Kein Klartext-Secret in values.yaml
- [ ] Alle Komponenten haben `enabled: true/false` Flag

## Nicht in diesem Ticket
- Komponenten-spezifische NetworkPolicies (ab TICKET-002)
- ExternalSecret-Templates (TICKET-004)
- Konkrete Komponenten-Konfigurationen (TICKET-002 ff.)
