#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$chart/../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq '{"globals": .globals}' "$root/apps/root/values.yaml" > "$tmp/globals.yaml"
helm template hermes-agent "$chart" --namespace prod --values "$tmp/globals.yaml" > "$tmp/rendered.yaml"
yq -o=json -I=0 '.' "$tmp/rendered.yaml" > "$tmp/resources.jsonl"
python3 - "$tmp/resources.jsonl" <<'PY'
import json
import sys

resources = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
def resource(kind, name):
    matches = [r for r in resources if r["kind"] == kind and r["metadata"]["name"] == name]
    assert len(matches) == 1, (kind, name, matches)
    return matches[0]

client = resource("AuthentikClient", "hermes-agent-dashboard")
assert client["spec"]["redirectUris"] == ["https://hermes.olsen.cloud/auth/callback"]
assert client["spec"]["signingKeyName"] == "authentik Self-signed Certificate"
assert client["spec"]["allowedGroups"] == [
    {"name": "hermes-agent-dashboard", "namespace": "prod"},
    {"name": "admin", "namespace": "shared"},
]
assert resource("AuthentikGroup", "hermes-agent-dashboard")["spec"]["members"] == []
assert len([r for r in resources if r["kind"] == "AuthentikClient"]) == 1
images = []
for name in ("hermes-agent-dashboard", "hermes-agent-gateway"):
    deployment = resource("Deployment", name)
    assert deployment["spec"]["strategy"]["type"] == "Recreate"
    pod = deployment["spec"]["template"]["spec"]
    assert pod["volumes"] == [{"name": "data", "persistentVolumeClaim": {"claimName": "hermes-agent-data"}}]
    container = pod["containers"][0]
    assert "command" not in container  # preserve upstream bootstrap
    assert container["volumeMounts"] == [{"name": "data", "mountPath": "/opt/data"}]
    assert "--insecure" not in container["args"]
    env = {e["name"]: e for e in container["env"]}
    assert "HERMES_DASHBOARD_INSECURE" not in env
    images.append(container["image"])
    if name.endswith("dashboard"):
        assert container["args"] == ["dashboard", "--host", "0.0.0.0", "--no-open", "--skip-build"]
        assert env["HERMES_DASHBOARD_PUBLIC_URL"]["value"] == "https://hermes.olsen.cloud"
        assert env["HERMES_DASHBOARD_OIDC_SCOPES"]["value"] == "openid profile email"
        for variable, key in (("ISSUER", "issuer"), ("CLIENT_ID", "clientId"), ("CLIENT_SECRET", "clientSecret")):
            entry = env["HERMES_DASHBOARD_OIDC_" + variable]
            assert "value" not in entry
            assert entry["valueFrom"]["secretKeyRef"] == {
                "name": "hermes-agent-dashboard-oidc-credentials", "key": key,
            }
    else:
        assert container["args"] == ["gateway", "run"]
assert images[0] == images[1] and "@sha256:" in images[0]
pvc = resource("PersistentVolumeClaim", "hermes-agent-data")
assert pvc["spec"]["storageClassName"] == "local-path"
assert pvc["spec"]["resources"]["requests"]["storage"] == "20Gi"
assert "Delete=false" in pvc["metadata"]["annotations"]["argocd.argoproj.io/sync-options"]
resource("ReplicationSource", "backup-hermes-agent-data")
routes = [r for r in resources if r["kind"] == "VirtualService"]
assert len(routes) == 1
assert routes[0]["spec"]["gateways"] == ["shared/private", "mesh"]
assert routes[0]["spec"]["hosts"] == ["hermes.olsen.cloud", "mesh"]
print("Hermes OIDC, private ingress, shared image, and retained storage render correctly")
PY
