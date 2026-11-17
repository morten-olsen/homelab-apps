#!/usr/bin/env bash
# Asserts the contract Aurboda needs from this chart: private-only exposure,
# the app wired to its own PostGIS, and the pg_dump/server major match.
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$chart/../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq '{"globals": .globals}' "$root/apps/root/values.yaml" > "$tmp/globals.yaml"
helm template aurboda "$chart" --namespace prod --values "$tmp/globals.yaml" > "$tmp/rendered.yaml"
yq -o=json -I=0 'select(.kind != null)' "$tmp/rendered.yaml" > "$tmp/all.json"
python3 - "$tmp/all.json" <<'PY'
import json
import sys

docs = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
def one(kind, name):
    found = [d for d in docs if d["kind"] == kind and d["metadata"]["name"] == name]
    assert len(found) == 1, f"expected one {kind}/{name}, found {len(found)}"
    return found[0]

app = one("Deployment", "aurboda")
db = one("Deployment", "aurboda-db")
one("Service", "aurboda-db")
for d in (app, db):
    assert d["spec"]["strategy"]["type"] == "Recreate", d["metadata"]["name"]

# The app reaches its own PostGIS with the generated password; the central DB
# is the server's default `postgres` database, as upstream's compose file.
c = app["spec"]["template"]["spec"]["containers"][0]
env = {e["name"]: e for e in c["env"]}
assert env["PGHOST"]["value"] == "aurboda-db"
assert env["PGUSER"]["value"] == "aurboda_service"
assert env["PGPASSWORD"]["valueFrom"]["secretKeyRef"] == {"name": "aurboda-secrets", "key": "dbPassword"}
assert env["SESSION_SECRET"]["valueFrom"]["secretKeyRef"] == {"name": "aurboda-session", "key": "sessionSecret"}
assert env["WEB_HOST"]["value"] == "https://aurboda.olsen.cloud"
assert env["API_BASE_URL"]["value"] == "https://aurboda.olsen.cloud/api"
# Passkeys in the Android app need assetlinks.json to trust the APK's signing key:
# the official GitHub-release APK (v1.0.3750, APK signature scheme v2 certificate).
assert env["ANDROID_APP_FINGERPRINTS"]["value"] == "80:EA:56:64:44:9D:8D:28:BC:8E:D0:EC:ED:AA:6A:4D:91:BD:B9:82:E2:AA:68:5C:4E:4C:D2:F9:8A:10:49:56"
# Home Assistant is only reachable at a private address (home-assistant.olsen.cloud);
# Morten accepted the SSRF widening while he is the only user. Calendars stay public-only.
assert env["HOME_ASSISTANT_ALLOW_PRIVATE_ADDRESSES"]["value"] == "true"
assert "CALENDAR_ALLOW_PRIVATE_ADDRESSES" not in env
# ALLOW_SIGNUP is migrated into the DB once and would override the admin setting.
assert "ALLOW_SIGNUP" not in env

dc = db["spec"]["template"]["spec"]["containers"][0]
denv = {e["name"]: e for e in dc["env"]}
assert denv["POSTGRES_USER"]["value"] == "aurboda_service"
assert denv["POSTGRES_PASSWORD"]["valueFrom"]["secretKeyRef"] == {"name": "aurboda-secrets", "key": "dbPassword"}
# The app image ships postgresql16-client for data export; pg_dump refuses a
# newer server major.
repo, tag = dc["image"].split("@")[0].rsplit(":", 1)
assert repo.endswith("postgis/postgis") and tag.startswith("16-"), dc["image"]
assert "@sha256:" in c["image"] and "@sha256:" in dc["image"], "images must be digest-pinned"

claims = {v["persistentVolumeClaim"]["claimName"] for v in db["spec"]["template"]["spec"]["volumes"] if "persistentVolumeClaim" in v}
assert claims == {"aurboda-db-data"}, claims
backups = [d for d in docs if d["kind"] == "ReplicationSource"]
assert [b["spec"]["sourcePVC"] for b in backups] == ["aurboda-db-data"], backups

# Personal health data: private gateway only.
vs = [d for d in docs if d["kind"] == "VirtualService"]
gateways = sorted({g for v in vs for g in v["spec"]["gateways"]} - {"mesh"})
assert gateways == ["shared/private"], gateways
for d in (app, db):
    for ctr in d["spec"]["template"]["spec"]["containers"]:
        assert "limits" in ctr.get("resources", {}) and "memory" in ctr["resources"]["limits"], ctr["name"]
# Aurboda requires SESSION_SECRET to be exactly 32 bytes (Buffer.from(secret).length).
gen = [d for d in docs if d["kind"] == "Password" and d["metadata"]["name"] == "aurboda-session-session-secret-generator"]
assert len(gen) == 1, gen
# A separate ExternalSecret: the DB password must never be regenerated with it.
es = [d for d in docs if d["kind"] == "ExternalSecret"]
refs = {e["metadata"]["name"]: [r["sourceRef"]["generatorRef"]["name"] for r in e["spec"]["dataFrom"]] for e in es}
assert refs.get("aurboda-session") == [gen[0]["metadata"]["name"]], refs
# The DB password's ExternalSecret keeps its first-rollout spec, so ESO never
# regenerates a password the initialised database does not know.
assert refs.get("aurboda-secrets") == ["aurboda-secrets-session-secret-generator", "aurboda-secrets-db-password-generator"], refs
spec = gen[0]["spec"]
per_char = {"raw": 1, "hex": 2}[spec.get("encoding", "raw")]
assert spec["length"] * per_char == 32, f"session secret renders {spec['length'] * per_char} bytes, Aurboda needs 32"
# Authentik SSO: the provider is added in Aurboda's admin UI, whose redirect
# URI is <API_BASE_URL>/auth/oidc/callback. The app returns via its own scheme.
client = one("AuthentikClient", "aurboda")
assert client["spec"]["redirectUris"] == ["https://aurboda.olsen.cloud/api/auth/oidc/callback"], client["spec"]["redirectUris"]
assert client["spec"].get("clientType", "confidential") == "confidential"
assert {"name": "admin", "namespace": "shared"} in client["spec"]["allowedGroups"], client["spec"]["allowedGroups"]
print("Aurboda renders private-only, wired to its own PostGIS 16 with a backed-up volume")
PY
