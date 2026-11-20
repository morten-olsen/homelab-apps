#!/usr/bin/env bash
# The client must stay public with the device code grant: the workforce CLI signs in with it. The
# image stays pinned by digest, and the route has no timeout, which would cut agents' WebSockets.
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$chart/../../.." && pwd)"
globals="$(mktemp)"
trap 'rm -f "$globals"' EXIT
yq '{"globals": .globals}' "$root/apps/root/values.yaml" >"$globals"
rendered="$(helm template workforce "$chart" --namespace prod --values "$globals")"
client="$(printf '%s\n' "$rendered" | yq 'select(.kind == "AuthentikClient")')"

[ "$(printf '%s\n' "$client" | yq '.spec.clientType')" = public ] || { echo "client is not public"; exit 1; }
printf '%s\n' "$client" | yq -e '.spec.grantTypes[] | select(. == "urn:ietf:params:oauth:grant-type:device_code")' >/dev/null ||
  { echo "client lacks the device code grant"; exit 1; }
[ "$(printf '%s\n' "$client" | yq '.spec.allowedGroups | length')" = 2 ] || { echo "client must allow workforce and shared/admin"; exit 1; }
image="$(printf '%s\n' "$rendered" | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image')"
case "$image" in *@sha256:*) ;; *) echo "image is not pinned by digest: $image"; exit 1 ;; esac
[ "$(printf '%s\n' "$rendered" | yq 'select(.kind == "VirtualService") | .spec.http[0].timeout')" = null ] ||
  { echo "the route must not time out"; exit 1; }
echo "ok"
