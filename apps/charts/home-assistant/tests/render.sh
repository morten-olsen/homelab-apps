#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$chart/../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq '{"globals": .globals}' "$root/apps/root/values.yaml" > "$tmp/globals.yaml"
helm template home-assistant "$chart" -n prod -f "$tmp/globals.yaml" > "$tmp/rendered.yaml"
yq -o=json '.' "$tmp/rendered.yaml" | jq -s '.' > "$tmp/objects.json"
python3 - "$tmp/objects.json" <<'PY'
import json,sys
objects=json.load(open(sys.argv[1]))
assert not any(x['kind']=='ConfigMap' and x['metadata']['name']=='home-assistant-dawarich-location' for x in objects), 'Inbound bridge ConfigMap remains'
dep=next(x for x in objects if x['kind']=='Deployment' and x['metadata']['name']=='home-assistant')
pod=dep['spec']['template']
assert 'checksum/dawarich-location' not in pod['metadata'].get('annotations',{})
assert not any(v['name']=='dawarich-location' for v in pod['spec']['volumes'])
container=pod['spec']['containers'][0]
assert not any(m['mountPath'].startswith('/config/custom_components/dawarich/') for m in container['volumeMounts'])
assert any(m['mountPath']=='/config' for m in container['volumeMounts'])
assert pod['spec']['hostNetwork'] is True
assert len(pod['spec']['containers'])==1 and dep['spec']['replicas']==1
assert container['resources']=={'requests':{'cpu':'100m','memory':'1Gi'},'limits':{'memory':'24Gi'}}
print('Restored HA chart: no inbound bridge; process, config mount and resources retained: PASS')
PY
