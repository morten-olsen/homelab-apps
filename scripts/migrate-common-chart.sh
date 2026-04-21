#!/usr/bin/env bash
# Migrates all app Chart.yaml files from file:// common reference
# to the published homelab-common chart on the Helm repo.
#
# Usage:
#   ./scripts/migrate-common-chart.sh [repo-url]
#
# Default repo URL: https://morten-olsen.github.io/homelab-apps

set -euo pipefail

REPO_URL="${1:-https://morten-olsen.github.io/homelab-apps}"
CHART_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHARTS_DIR="$SCRIPT_DIR/../apps/charts"

count=0

for chart_yaml in "$CHARTS_DIR"/*/Chart.yaml; do
  if grep -q 'file://../../common' "$chart_yaml"; then
    sed -i '' \
      -e 's/name: common/name: homelab-common/' \
      -e "s|version: 1.0.0|version: $CHART_VERSION|" \
      -e "s|repository: file://../../common|repository: $REPO_URL|" \
      "$chart_yaml"
    count=$((count + 1))
    echo "  migrated: $(basename "$(dirname "$chart_yaml")")"
  fi
done

echo ""
echo "Migrated $count charts to homelab-common @ $REPO_URL"
echo ""
echo "Next steps:"
echo "  1. Run 'helm repo add homelab-apps $REPO_URL' (if not already added)"
echo "  2. Run 'helm dependency build' in each chart directory"
echo "  3. Verify with 'helm template <name> <chart-dir> --set globals.environment=prod --set globals.domain=example.com'"
