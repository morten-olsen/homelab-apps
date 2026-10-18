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
        assert entity.extra_state_attributes=={'location_status':'fresh','recorded_at':'1970-01-01T00:16:40+00:00','last_seen':1000,'stale_notification_sent':False}
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
SETUP_RUNTIME = r'''
import asyncio,importlib.util,pathlib,tempfile,sys,json
from unittest.mock import MagicMock,AsyncMock
from homeassistant.core import HomeAssistant

async def main():
 files=BUNDLE
 with tempfile.TemporaryDirectory() as tmp:
  for name,content in files.items(): pathlib.Path(tmp,name).write_text(content)
  pathlib.Path(tmp,'manifest.json').write_text(pathlib.Path('/config/custom_components/dawarich/manifest.json').read_text())
  spec=importlib.util.spec_from_file_location('probe_dawarich',pathlib.Path(tmp,'__init__.py'),submodule_search_locations=[tmp,'/config/custom_components/dawarich'])
  module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
  hass=HomeAssistant(tmp)
  from homeassistant.helpers import frame
  frame.async_setup(hass)
  hass.config_entries=MagicMock()
  hass.config_entries.async_forward_entry_setups=AsyncMock()
  blocked=asyncio.Event()
  api=MagicMock(get_stats=AsyncMock(side_effect=blocked.wait),health=AsyncMock(side_effect=blocked.wait))
  module.get_api=lambda *args: api
  entry=MagicMock(entry_id=module.LOCATION_POLICY['entry_id'],data={'mobile_app':None,'host':'fixture','api_key':'fixture','ssl':True,'verify_ssl':True})
  from homeassistant.config_entries import current_entry
  current_entry.set(entry)
  from homeassistant.config_entries import ConfigEntryState
  entry.state=ConfigEntryState.SETUP_IN_PROGRESS
  tasks=[]
  def background(hass,coro,name):
   task=asyncio.create_task(coro);tasks.append(task);return task
  entry.async_create_background_task=background
  try:
   result=await asyncio.wait_for(module.async_setup_entry(hass,entry),timeout=.5)
   assert result is True
   assert 'device_tracker' in hass.config_entries.async_forward_entry_setups.call_args.args[1]
   print('HA setup forwards GPS platform while optional stats/version network calls are blocked: PASS')
  finally:
   for task in tasks: task.cancel()
   await asyncio.gather(*tasks,return_exceptions=True)
   await hass.async_stop()
asyncio.run(main())
'''
result = subprocess.run(['kubectl', 'exec', '-i', '-n', 'prod', 'deployment/home-assistant',
                         '-c', 'home-assistant', '--', 'python', '-'], input=source, text=True)
if result.returncode:
    raise SystemExit(result.returncode)
setup_source = SETUP_RUNTIME.replace('files=BUNDLE', 'files=' + repr(files))
result = subprocess.run(['kubectl', 'exec', '-i', '-n', 'prod', 'deployment/home-assistant',
                         '-c', 'home-assistant', '--', 'python', '-'], input=setup_source, text=True)
if result.returncode:
    raise SystemExit(result.returncode)
AUTOMATION_RUNTIME = r'''
import asyncio,json,tempfile,time,logging
logging.getLogger("homeassistant.loader").setLevel(logging.ERROR)
from unittest.mock import MagicMock
from homeassistant.core import HomeAssistant
from homeassistant.helpers.template import Template
from homeassistant.components.automation.config import async_validate_config_item
from homeassistant.helpers import frame

async def main():
 config=CONFIG
 with tempfile.TemporaryDirectory() as tmp:
  hass=HomeAssistant(tmp);frame.async_setup(hass)
  from homeassistant import loader
  loader.async_setup(hass)
  from homeassistant.helpers import trigger
  await trigger.async_setup(hass)
  hass.config_entries=MagicMock()
  await async_validate_config_item(hass,config['id'],config)
  template=Template(config['conditions'][0]['value_template'],hass)
  now=time.time()
  cases=[(None,False,False),(now-86399,False,False),(now-86401,False,True),(now-86401,True,False)]
  for timestamp,sent,expected in cases:
   attrs={'stale_notification_sent':sent}
   if timestamp: attrs['last_seen']=timestamp
   hass.states.async_set('device_tracker.dawarich_morten','unavailable',attrs)
   assert template.async_render()==expected
  print('Native HA automation schema and template: threshold, unknown timestamp, unavailable tracker and dedup: PASS')
  await hass.async_stop()
asyncio.run(main())
'''
automation = json.loads(subprocess.check_output(['yq', '-o=json', '.', str(chart / 'files/stale-automation.yaml')], text=True))
automation_source = AUTOMATION_RUNTIME.replace('config=CONFIG', 'config=' + repr(automation))
result = subprocess.run(['kubectl', 'exec', '-i', '-n', 'prod', 'deployment/home-assistant',
                         '-c', 'home-assistant', '--', 'python', '-'], input=automation_source, text=True)
raise SystemExit(result.returncode)
