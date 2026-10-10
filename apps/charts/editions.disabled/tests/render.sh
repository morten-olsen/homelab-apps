#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
helm repo add editions-common https://mortenolsen.pro/homelab-core/ >/dev/null
helm dependency build "$chart" >/dev/null
globals="$(mktemp)"
trap 'rm -f "$globals"' EXIT
yq '{"globals": .globals}' "$chart/../../root/values.yaml" >"$globals"
json="$(helm template editions "$chart" --namespace prod --values "$globals" "$@" | yq -o=json -I=0 '.' | jq -s '.')"
jq -e '
  ([.[] | select(.kind == "Deployment") | .spec.template.spec.containers[]
    | select(.name == "editions")
    | .resources.requests.memory == "512Mi" and .resources.limits.memory == "1536Mi"
      and .resources.requests.cpu == "250m" and .resources.limits.cpu == "2"
      and any(.env[]; .name == "NODE_OPTIONS" and .value == "--max-old-space-size=256")]
    == [true]) and
  ([.[] | select(.kind == "Deployment") | .spec.template.spec.initContainers[]
    | .resources.requests.memory == "16Mi" and .resources.limits.memory == "64Mi"] == [true]) and
  any(.[]; .kind == "PersistentVolumeClaim" and .metadata.name == "editions-data"
    and .metadata.annotations["argocd.argoproj.io/sync-options"] == "Delete=false")
' <<<"$json" >/dev/null
printf 'Editions resource ceilings and preserved PVC verified\n'
