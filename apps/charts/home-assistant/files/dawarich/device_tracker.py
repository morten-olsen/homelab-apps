"""Read Dawarich points using the existing entry; use HA's GPS zone handling."""
from datetime import UTC, datetime, timedelta
import json
import logging
from pathlib import Path
import time

from homeassistant.components.device_tracker.config_entry import TrackerEntity
from homeassistant.components.person import async_add_user_device_tracker
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.storage import Store
from homeassistant.helpers.start import async_at_started
from homeassistant.helpers.update_coordinator import CoordinatorEntity, DataUpdateCoordinator

from .location import PointFeed, fetch_latest

_LOGGER = logging.getLogger(__name__)
POLICY = json.loads((Path(__file__).parent / 'location-policy.json').read_text())


async def async_setup_entry(hass, entry, async_add_entities):
    if entry.entry_id != POLICY['entry_id']:
        return
    store = Store(hass, 1, 'dawarich_location.' + entry.entry_id)
    saved = await store.async_load() or {}

    async def save(timestamp):
        # Never persist coordinates or credentials; only prevent time regression.
        await store.async_save({'high_water': timestamp})

    feed = PointFeed(save=save, high_water=saved.get('high_water', 0),
                     stale_seconds=POLICY['stale_seconds'])
    session = async_get_clientsession(hass)

    async def update():
        now = time.time()
        async def fetch():
            return await fetch_latest(session, POLICY['url'], entry.data['api_key'], now=now)
        await feed.poll(fetch, now=now)
        return (feed.status, feed.point)

    coordinator = DataUpdateCoordinator(
        hass, _LOGGER, name='Dawarich location', config_entry=entry,
        update_method=update, update_interval=timedelta(seconds=POLICY['poll_seconds']),
        always_update=False,
    )
    await coordinator.async_config_entry_first_refresh()
    async_add_entities([DawarichLocation(coordinator, feed, entry)])


class DawarichLocation(CoordinatorEntity, TrackerEntity):
    _attr_name = 'Dawarich Morten'
    _attr_icon = 'mdi:map-marker'

    def __init__(self, coordinator, feed, entry):
        super().__init__(coordinator)
        self.feed = feed
        self._attr_unique_id = entry.entry_id + '/location'

    async def async_added_to_hass(self):
        await super().async_added_to_hass()
        self.async_on_remove(async_at_started(self.hass, self._attach_person))

    async def _attach_person(self, hass):
        # HA appends to the existing person, retaining ID, image and other trackers.
        await async_add_user_device_tracker(hass, POLICY['person_user_id'], self.entity_id)

    @property
    def available(self):
        return self.coordinator.last_update_success and self.feed.available

    @property
    def latitude(self):
        return self.feed.point.latitude if self.feed.point else None

    @property
    def longitude(self):
        return self.feed.point.longitude if self.feed.point else None

    @property
    def location_accuracy(self):
        return self.feed.point.accuracy if self.feed.point else 0

    @property
    def extra_state_attributes(self):
        attributes = {'location_status': self.feed.status}
        if point := self.feed.point:
            attributes['recorded_at'] = datetime.fromtimestamp(point.timestamp, UTC).isoformat()
            attributes['last_seen'] = point.timestamp
        return attributes
