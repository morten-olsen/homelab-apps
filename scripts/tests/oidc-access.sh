#!/usr/bin/env bash
# Validate changed application enrollment using built dependencies. Does not
# download or publish packages; invoke after dependency build in normal CI.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq '{"globals": .globals}' "$root/apps/root/values.yaml" > "$tmp/globals.yaml"
for name in audiobookshelf bytestash coder dawarich dragonfly forgejo home-assistant immich jellyfin mealie memos miniflux netbird openwebui tandoor vikunja windmill; do
  chart="$root/apps/charts/$name"
  helm lint "$chart" --values "$tmp/globals.yaml" > /dev/null
  helm template "$name" "$chart" --namespace prod --values "$tmp/globals.yaml" > "$tmp/rendered.yaml"
  yq -o=json -I=0 'select(.kind == "AuthentikGroup" or .kind == "AuthentikClient")' "$tmp/rendered.yaml" > "$tmp/identity.json"
  python3 - "$name" "$tmp/identity.json" <<'PYTEST'
import json
import sys
name = sys.argv[1]
objects = [json.loads(line) for line in open(sys.argv[2])]
groups = [x for x in objects if x['kind'] == 'AuthentikGroup']
clients = [x for x in objects if x['kind'] == 'AuthentikClient']
assert len(groups) == len(clients) == 1, (name, objects)
assert groups[0]['metadata']['name'] == clients[0]['metadata']['name'] == name
assert groups[0]['spec']['members'] == [], name
assert clients[0]['spec']['allowedGroups'] == [{'name': name, 'namespace': 'prod'}, {'name': 'admin', 'namespace': 'shared'}], name
assert groups[0]['spec']['serverRef'] == clients[0]['spec']['serverRef'] == {'name': 'authentik', 'namespace': 'shared'}, name
print(f'ok: {name} has one app group plus additive admin, without implicit membership')
PYTEST
done
