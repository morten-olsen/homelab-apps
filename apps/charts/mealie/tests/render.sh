#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$chart/../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 -m unittest discover -s "$chart/tests" -p 'test_*.py'
yq '{"globals": .globals}' "$root/apps/root/values.yaml" > "$tmp/globals.yaml"
helm template mealie "$chart" --namespace prod --values "$tmp/globals.yaml" > "$tmp/rendered.yaml"
yq -o=json -I=0 'select(.kind == "AuthentikClient")' "$tmp/rendered.yaml" > "$tmp/client.json"
yq -o=json -I=0 'select(.kind == "Deployment")' "$tmp/rendered.yaml" > "$tmp/deployment.json"
python3 - "$tmp/client.json" "$tmp/deployment.json" <<'PY'
import json
import sys
client = json.load(open(sys.argv[1]))
deployment = json.load(open(sys.argv[2]))
scopes = client["spec"]["scopes"]
assert scopes == ["openid", "profile", "mealie-email"], scopes
env = {e["name"]: e.get("value") for e in deployment["spec"]["template"]["spec"]["containers"][0]["env"]}
assert env["OIDC_SCOPES_OVERRIDE"].split() == scopes, env["OIDC_SCOPES_OVERRIDE"]
assert env["OIDC_REQUIRES_EMAIL_VERIFICATION"] == "true"
assert env.get("OIDC_USER_CLAIM", "email") == "email"
assert env["OIDC_AUTH_ENABLED"] == "true"
assert client["spec"]["redirectUris"] == ["https://mealie.olsen.cloud/login"]
print("Mealie scope selection and verified-email gate render correctly")
PY
