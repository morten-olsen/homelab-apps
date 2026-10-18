"""Read Dawarich points using the existing entry; use HA's GPS zone handling."""
from datetime import UTC, datetime, timedelta
from dataclasses import dataclass
import json
import logging
from pathlib import Path
import time

from homeassistant.components.device_tracker.config_entry import TrackerEntity
from homeassistant.components.person import async_add_user_device_tracker
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.storage import Store
from homeassistant.helpers.start import async_at_started
from homeassistant.helpers.update_coordinator import CoordinatorEntity, DataUpdateCoordinator

from .location import PointFeed, fetch_latest
from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)
POLICY = json.loads((Path(__file__).parent / 'location-policy.json').read_text())


@dataclass
class LocationData:
    coordinator: DataUpdateCoordinator
    feed: PointFeed


async def async_prepare_location(hass, entry):
    store = Store(hass, 1, 'dawarich_location.' + entry.entry_id)
    saved = await store.async_load() or {}

    async def save(state):
        # Never persist coordinates or credentials, only epoch and notification gate.
        await store.async_save(state)

    feed = PointFeed(save=save, high_water=saved.get('high_water', 0),
                     stale_seconds=POLICY['stale_seconds'], alerted=saved.get('alerted', False))
    session = async_get_clientsession(hass)

    async def update():
        now = time.time()
        async def fetch():
            return await fetch_latest(session, POLICY['url'], entry.data['api_key'], now=now)
        await feed.poll(fetch, now=now)
        return (feed.status, feed.point, feed.alerted)

    coordinator = DataUpdateCoordinator(
        hass, _LOGGER, name='Dawarich location', config_entry=entry,
        update_method=update, update_interval=timedelta(seconds=POLICY['poll_seconds']),
        always_update=False,
    )
    await coordinator.async_config_entry_first_refresh()
    return LocationData(coordinator, feed)


async def async_setup_entry(hass, entry, async_add_entities):
    if (location := entry.runtime_data.location) is None:
        return
    coordinator, feed = location.coordinator, location.feed

    async def acknowledge(call):
        try:
            await feed.acknowledge_alert(now=time.time())
        except Exception:
            raise HomeAssistantError('Could not persist location notification acknowledgement') from None
        coordinator.async_set_updated_data((feed.status, feed.point, feed.alerted))

    hass.services.async_register(DOMAIN, 'acknowledge_stale_location', acknowledge)
    entry.async_on_unload(lambda: hass.services.async_remove(DOMAIN, 'acknowledge_stale_location'))
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
        attributes = {'location_status': self.feed.status, 'stale_notification_sent': self.feed.alerted}
        if self.feed.high_water > 0:
            attributes['recorded_at'] = datetime.fromtimestamp(self.feed.high_water, UTC).isoformat()
            attributes['last_seen'] = self.feed.high_water
        return attributes
