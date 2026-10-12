#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
helm dependency update "$chart" >/dev/null
helm template woodpecker "$chart" --namespace prod \
  --values "$chart/../../root/values.yaml" \
  --show-only templates/agent-deployment.yaml | yq -o=json '.' | jq -e '
    .spec.strategy.type == "Recreate" and
    ([.spec.template.spec.containers[0].env[] | select(
      (.name == "WOODPECKER_BACKEND_K8S_STORAGE_CLASS" and .value == "woodpecker-ci") or
      (.name == "WOODPECKER_BACKEND_K8S_STORAGE_RWX" and .value == "false") or
      (.name == "WOODPECKER_MAX_WORKFLOWS" and .value == "2"))] | length == 3)
  ' >/dev/null
echo 'ok: one agent at rollout, with RWO CI disk workspaces and bounded concurrency'
