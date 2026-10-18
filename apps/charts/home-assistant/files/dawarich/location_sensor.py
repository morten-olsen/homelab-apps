"""Keep the recorded clock readable when HA drops unavailable GPS attributes."""
from datetime import UTC, datetime

from homeassistant.components.sensor import SensorEntity, SensorDeviceClass
from homeassistant.const import EntityCategory
from homeassistant.helpers.update_coordinator import CoordinatorEntity


class DawarichLocationTimestamp(CoordinatorEntity, SensorEntity):
    _attr_name = 'Dawarich Last Recorded Location'
    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, location, entry, device_info):
        super().__init__(location.coordinator)
        self.feed = location.feed
        self._attr_unique_id = entry.entry_id + '/last_recorded_location'
        self._attr_device_info = device_info

    @property
    def available(self):
        # Local persisted metadata stays valid even when remote location is stale.
        return True

    @property
    def native_value(self):
        if self.feed.high_water > 0:
            return datetime.fromtimestamp(self.feed.high_water, UTC)
        return None

    @property
    def extra_state_attributes(self):
        return {'location_status': self.feed.status,
                'stale_notification_sent': self.feed.alerted,
                'accuracy_m': self.feed.point.accuracy if self.feed.point else None}
