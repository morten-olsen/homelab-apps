#!/usr/bin/env bash
# Renders and checks every chart under apps/charts the way the ApplicationSet deploys it:
#   1. helm lint with the ApplicationSet's globals (apps/root/values.yaml)
#   2. helm template piped through kubeconform (CRDs have no schema here and are skipped)
#   3. the chart's own tests/render.sh, where one exists
# Needs helm, yq, jq and kubeconform (mise install). Usage: scripts/ci/validate-charts.sh [chart-dir...]
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The ApplicationSet passes .Values.globals to every chart as inline helm values.
yq '{"globals": .globals}' "$root/apps/root/values.yaml" >"$tmp/globals.yaml"

if [ "$#" -gt 0 ]; then charts=("$@"); else charts=("$root"/apps/charts/*/); fi

failed=()
for chart in "${charts[@]}"; do
  chart="${chart%/}"
  name="$(basename "$chart")"
  echo "::: $name"
  ok=1
  step() {
    local what="$1"
    shift
    if ! "$@" >"$tmp/out" 2>&1; then
      echo "FAIL $name: $what"
      sed 's/^/    /' "$tmp/out"
      ok=0
    fi
  }
  # dependency build needs each repository registered first
  while read -r url; do
    [ -n "$url" ] && helm repo add "r-$(printf '%s' "$url" | cksum | cut -d' ' -f1)" "$url" >/dev/null 2>&1
  done < <(yq '.dependencies[].repository' "$chart/Chart.yaml" 2>/dev/null | sort -u | grep '^http')
  step "helm dependency build" helm dependency build "$chart"
  if [ "$ok" = 1 ]; then
    step "helm lint" helm lint "$chart" --values "$chart/values.yaml" --values "$tmp/globals.yaml"
    if helm template "${name%.disabled}" "$chart" --namespace prod --values "$tmp/globals.yaml" >"$tmp/rendered.yaml" 2>"$tmp/out"; then
      step "kubeconform" kubeconform -strict -kubernetes-version 1.33.4 -ignore-missing-schemas -summary "$tmp/rendered.yaml"
    else
      echo "FAIL $name: helm template"
      sed 's/^/    /' "$tmp/out"
      ok=0
    fi
    if [ -x "$chart/tests/render.sh" ]; then
      step "tests/render.sh" "$chart/tests/render.sh"
    fi
  fi
  [ "$ok" = 1 ] || failed+=("$name")
done

if [ "${#failed[@]}" -ne 0 ]; then
  printf '\n%s chart(s) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
  exit 1
fi
printf '\nall charts passed\n'
