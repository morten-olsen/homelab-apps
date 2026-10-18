#!/usr/bin/env bash
set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$chart/../../.." && pwd)"
python3 -m unittest discover -s "$chart/tests" -p 'test_*.py'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq '{"globals": .globals}' "$root/apps/root/values.yaml" > "$tmp/globals.yaml"
helm template home-assistant "$chart" -n prod -f "$tmp/globals.yaml" > "$tmp/rendered.yaml"
yq -o=json '.' "$tmp/rendered.yaml" | jq -s '.' > "$tmp/objects.json"
python3 - "$tmp/objects.json" <<'PY'
import json,sys
objects=json.load(open(sys.argv[1]))
dep=next(x for x in objects if x['kind']=='Deployment' and x['metadata']['name']=='home-assistant')
pod=dep['spec']['template']
cm=next(x for x in objects if x['kind']=='ConfigMap' and x['metadata']['name']=='home-assistant-dawarich-location')
assert set(cm['data']) == {'__init__.py','device_tracker.py','location.py','location-policy.json','stale-automation.json'}
mounts=pod['spec']['containers'][0]['volumeMounts']
for f in cm['data']:
    assert any(m['mountPath']=='/config/custom_components/dawarich/'+f and m.get('readOnly') and m['subPath']==f for m in mounts), f
assert len(pod['metadata']['annotations']['checksum/dawarich-location']) == 64
assert pod['spec']['hostNetwork'] is True
assert len(pod['spec']['containers']) == 1
assert pod['spec']['containers'][0]['resources']['limits']['memory']=='24Gi'
policy=json.loads(cm['data']['location-policy.json'])
assert policy['entry_id']=='01KQVN8547CAQH77C3T7TAHH0M'
assert policy['url']=='https://dawarich.olsen.cloud'
assert policy['poll_seconds']==30 and policy['stale_seconds']==900
PY

python3 - "$tmp/objects.json" <<'PYTEST'
import json,sys
objects=json.load(open(sys.argv[1]))
cm=next(x for x in objects if x['kind']=='ConfigMap')
a=json.loads(cm['data']['stale-automation.json'])
assert a['id']=='dawarich_location_stale_24h'
assert a['triggers']==[{'trigger':'homeassistant','event':'start'},{'trigger':'time_pattern','minutes':'/5'}]
assert a['actions'][0]['target']['entity_id']=='notify.home'
assert a['actions'][1]['action']=='dawarich.acknowledge_stale_location'
assert 'last_updated' not in a['conditions'][0]['value_template']
assert 'for' not in a['triggers'][0] and 'for' not in a['triggers'][1]
PYTEST
