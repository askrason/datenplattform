#!/bin/bash
# generate-schema.sh – Konvertiere values.schema.yaml → values.schema.json
#
# Das Helm Chart kann sowohl YAML- als auch JSON-Schema verwenden.
# Dieses Skript generiert die JSON-Version aus der YAML-Version.
#
# Abhängigkeiten:
#   - yq (https://github.com/mikefarah/yq) – YAML ↔ JSON Konversion
#   - oder: python3 + PyYAML
#
# Installation (falls nicht vorhanden):
#   macOS:  brew install yq
#   Linux:  sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
#   Docker: docker run -i mikefarah/yq . < values.schema.yaml > values.schema.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/.."
SCHEMA_YAML="$CHART_DIR/values.schema.yaml"
SCHEMA_JSON="$CHART_DIR/values.schema.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "values.schema.yaml → values.schema.json"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Prüfe ob source-Datei existiert
if [ ! -f "$SCHEMA_YAML" ]; then
    echo "❌ FEHLER: $SCHEMA_YAML nicht gefunden"
    exit 1
fi

# Versuche mit yq (bevorzugt)
if command -v yq &> /dev/null; then
    echo "📦 Nutze yq für Konversion..."
    yq eval -o=json "$SCHEMA_YAML" > "$SCHEMA_JSON"
    echo "✅ Schema generiert: $SCHEMA_JSON"

# Fallback auf python3 + PyYAML
elif command -v python3 &> /dev/null; then
    echo "📦 Nutze python3 + PyYAML für Konversion..."
    python3 << 'PYTHON_SCRIPT'
import yaml
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        yaml_data = yaml.safe_load(f)

    with open(sys.argv[2], 'w') as f:
        json.dump(yaml_data, f, indent=2)

    print(f"✅ Schema generiert: {sys.argv[2]}")
except Exception as e:
    print(f"❌ FEHLER: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    python3 - "$SCHEMA_YAML" "$SCHEMA_JSON"

# Fallback auf jq (falls nur JSON-Tools vorhanden)
elif command -v jq &> /dev/null; then
    echo "⚠️  jq benötigt ein YAML-Parser – bitte yq oder python3 installieren"
    exit 1

else
    echo "❌ FEHLER: Keiner der benötigten Tools vorhanden:"
    echo "   - yq       (empfohlen): brew install yq"
    echo "   - python3  (fallback):  apt-get install python3 python3-yaml"
    echo
    echo "Docker-Variante:"
    echo "   docker run -v \$(pwd):/work -w /work mikefarah/yq -o=json values.schema.yaml > values.schema.json"
    exit 1
fi

echo

# Validiere das generierte JSON
if command -v jq &> /dev/null; then
    echo "🔍 Validiere generiertes JSON..."
    if jq empty "$SCHEMA_JSON" 2>/dev/null; then
        echo "✓ JSON ist valide"
    else
        echo "⚠️  JSON ist syntaktisch ungültig – bitte values.schema.yaml prüfen"
        exit 1
    fi
    echo
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ FERTIG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Das generierte Schema kann in IDEs (VSCode, IntelliJ, etc.) zur Validation"
echo "von values.yaml-Files verwendet werden. Mehr Info:"
echo "  https://json-schema.org"
echo
