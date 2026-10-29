"""Check migrated Authentik enrollment at the rendered-manifest seam."""
import json
import sys

objects = [json.loads(line) for line in open(sys.argv[1])]
groups = {(x['metadata']['namespace'], x['metadata']['name']): x for x in objects if x['kind'] == 'AuthentikGroup'}
clients = [x for x in objects if x['kind'] == 'AuthentikClient']
for client in clients:
    key = (client['metadata']['namespace'], client['metadata']['name'])
    assert key in groups, ('missing single-owned application group', key)
    own = {'name': key[1], 'namespace': key[0]}
    allowed = client['spec']['allowedGroups']
    assert own in allowed, ('app group was replaced', key)
    assert {'name': 'admin', 'namespace': 'shared'} in allowed, ('current app missing explicit admin grant', key)
    assert len({(x['namespace'], x['name']) for x in allowed}) == len(allowed), ('duplicate grant', key)
    assert groups[key]['spec']['serverRef'] == client['spec']['serverRef'], key
    assert set(groups[key]['spec']) == {'serverRef', 'members'}, ('unexpected privilege field', key)
    print(f'ok: {key[0]}/{key[1]} has its app group and explicit administrator access')
