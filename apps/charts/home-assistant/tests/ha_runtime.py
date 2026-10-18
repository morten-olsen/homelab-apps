"""Run bridge compatibility and read-only API acceptance in the installed HA runtime.

Invoke with python3 apps/charts/home-assistant/tests/ha_runtime.py.
Uses temporary files; prints metadata only, never credentials or coordinates.
"""
from pathlib import Path
import json
import subprocess

RUNTIME = r'''
import asyncio,importlib.util,json,pathlib,sys,tempfile
from unittest.mock import MagicMock
from datetime import UTC,datetime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator
from homeassistant.const import EntityStateAttribute
from homeassistant.components.device_tracker.const import SourceType
from homeassistant.config_entries import ConfigEntry
from homeassistant.helpers.aiohttp_client import async_get_clientsession
import logging

async def main():
    files = BUNDLE
    compile(files['__init__.py'], '__init__.py', 'exec')
    with tempfile.TemporaryDirectory() as tmp:
        for name, content in files.items(): pathlib.Path(tmp, name).write_text(content)
        for name in ['location','device_tracker']:
            spec=importlib.util.spec_from_file_location('custom_components.dawarich.'+name,pathlib.Path(tmp,name+'.py'))
            module=importlib.util.module_from_spec(spec)
            sys.modules[spec.name]=module
            spec.loader.exec_module(module)
        dt=sys.modules['custom_components.dawarich.device_tracker']
        loc=sys.modules['custom_components.dawarich.location']
        hass=HomeAssistant(tmp)
        async def save(value): pass
        feed=loc.PointFeed(save=save)
        async def fixture(): return [{'timestamp':1000,'latitude':1,'longitude':2,'accuracy':8}]
        await feed.poll(fixture,now=1001)
        c=DataUpdateCoordinator(hass,logging.getLogger('test'),config_entry=None,name='test')
        entity=dt.DawarichLocation(c,feed,MagicMock(entry_id='fixture'))
        assert entity.available and entity.source_type==SourceType.GPS
        assert entity.latitude==1 and entity.longitude==2 and entity.location_accuracy==8
        assert entity.extra_state_attributes=={'location_status':'fresh','recorded_at':'1970-01-01T00:16:40+00:00','last_seen':1000}
        await feed.poll(fixture,now=1901)
        assert not entity.available and entity.extra_state_attributes['location_status']=='stale'
        class People:
            def __init__(self):
                self.person={'id':'morten','name':'Morten','user_id':dt.POLICY['person_user_id'],
                             'device_trackers':['device_tracker.existing'], 'picture':'existing-picture'}
            def async_items(self): return [self.person]
            async def async_update_item(self, person_id, data):
                assert person_id == 'morten'
                self.person.update(data)
        people=People()
        hass.data['person']=(None,people,None)
        entity.entity_id='device_tracker.dawarich_morten'
        await entity._attach_person(hass)
        await entity._attach_person(hass)
        assert people.person['device_trackers']==['device_tracker.existing','device_tracker.dawarich_morten']
        assert people.person['picture']=='existing-picture'
        print('Existing person identity, picture and tracker associations preserved; association idempotent: PASS')
        print('HA 2026.10.2 TrackerEntity imports, GPS source, accuracy, recorded timestamp and stale availability: PASS')
        # Exercise real network adapter and existing credential without printing payload.
        entries=json.loads(pathlib.Path('/config/.storage/core.config_entries').read_text())['data']['entries']
        entry=next(e for e in entries if e['entry_id']==dt.POLICY['entry_id'])
        import aiohttp
        async with aiohttp.ClientSession() as session:
            rows=await loc.fetch_latest(session,dt.POLICY['url'],entry['data']['api_key'],now=datetime.now(UTC).timestamp())
        await feed.poll(lambda: asyncio.sleep(0,result=rows),now=datetime.now(UTC).timestamp())
        print('real API adapter:',feed.status,'recorded_at:',entity.extra_state_attributes['recorded_at'],'accuracy:',entity.location_accuracy)
        await hass.async_stop()

asyncio.run(main())
'''

chart = Path(__file__).parents[1]
files = {p.name: p.read_text() for p in (chart / 'files/dawarich').glob('*.py')}
policy = subprocess.check_output(['yq', '-o=json', '.dawarichLocation', str(chart / 'values.yaml')], text=True)
files['location-policy.json'] = policy
source = RUNTIME.replace('files = BUNDLE', 'files = ' + repr(files))
result = subprocess.run(['kubectl', 'exec', '-i', '-n', 'prod', 'deployment/home-assistant',
                         '-c', 'home-assistant', '--', 'python', '-'], input=source, text=True)
raise SystemExit(result.returncode)
