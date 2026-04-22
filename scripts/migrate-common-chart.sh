#!/usr/bin/env bash
# Migrates all app charts from file:// common reference to the
# published homelab-common chart, and updates template includes
# to the new scoped API.
#
# Usage:
#   ./scripts/migrate-common-chart.sh [repo-url]
#
# Default repo URL: https://mortenolsen.pro/homelab-core/

set -euo pipefail

REPO_URL="${1:-https://mortenolsen.pro/homelab-core/}"
CHART_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHARTS_DIR="$SCRIPT_DIR/../apps/charts"

chart_count=0
template_count=0

echo "Migrating Chart.yaml dependencies..."
for chart_yaml in "$CHARTS_DIR"/*/Chart.yaml; do
  if grep -q 'file://../../common' "$chart_yaml"; then
    sed -i '' \
      -e 's/name: common/name: homelab-common/' \
      -e "s|version: 1.0.0|version: $CHART_VERSION|" \
      -e "s|repository: file://../../common|repository: $REPO_URL|" \
      "$chart_yaml"
    chart_count=$((chart_count + 1))
    echo "  chart: $(basename "$(dirname "$chart_yaml")")"
  fi
done

echo ""
# Only entry point templates get the scoped API — NOT helpers like
# common.fullname, common.labels, common.volumes, etc.
ENTRY_POINTS="common\.all|common\.deployment|common\.serviceAccount|common\.service|common\.pvc|common\.virtualService|common\.serviceEntry|common\.dns|common\.oidc|common\.database|common\.externalSecrets|common\.probe|common\.backup"

echo "Migrating template includes to scoped API..."
for template_dir in "$CHARTS_DIR"/*/templates; do
  [ -d "$template_dir" ] || continue
  for tpl in "$template_dir"/*.yaml "$template_dir"/*.tpl; do
    [ -f "$tpl" ] || continue
    if grep -q "include \"common\." "$tpl"; then
      # Only rewrite entry point calls, leave helpers unchanged
      # {{ include "common.deployment" . }}  ->  {{ include "common.deployment" (list . .Values) }}
      sed -i '' \
        -E "s/\{\{([- ]*)include \"(${ENTRY_POINTS})\" \. \}\}/\{\{\1include \"\2\" (list . .Values) \}\}/g" \
        "$tpl"
      template_count=$((template_count + 1))
      echo "  template: $(basename "$(dirname "$(dirname "$tpl")")")/$(basename "$tpl")"
    fi
  done
done

echo ""
echo "Migrated $chart_count charts and $template_count template files"
echo ""
echo "Next steps:"
echo "  1. Run 'helm repo add homelab https://mortenolsen.pro/homelab-core/' (if not already added)"
echo "  2. Run 'helm dependency build' in each chart directory"
echo "  3. Verify with 'helm template <name> <chart-dir> --set globals.environment=prod --set globals.domain=example.com'"
