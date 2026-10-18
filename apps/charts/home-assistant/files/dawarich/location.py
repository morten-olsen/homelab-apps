"""Bounded, monotonic location feed. No HTTP/HA dependency or sensitive logging."""
from dataclasses import dataclass
import math
import json


@dataclass(frozen=True, repr=False)
class Point:
    timestamp: int
    latitude: float
    longitude: float
    accuracy: float


class PointFeed:
    def __init__(self, *, save, high_water=0, stale_seconds=900):
        self.save = save
        self.high_water = high_water
        self.stale_seconds = stale_seconds
        self.point = None
        self.status = 'empty'

    @property
    def available(self):
        return self.status == 'fresh'

    async def poll(self, fetch, *, now):
        try:
            rows = await fetch()
        except Exception:
            # Exceptions can include an authorization header, URL or response.
            self.status = 'error'
            return
        if not isinstance(rows, list) or len(rows) > 1:
            self.status = 'invalid'
            return
        if not rows:
            self.status = 'empty'
            return
        try:
            row = rows[0]
            raw = [row[k] for k in ('timestamp', 'latitude', 'longitude', 'accuracy')]
            if any(isinstance(value, bool) for value in raw):
                raise ValueError
            timestamp, latitude, longitude, accuracy = map(float, raw)
            if not all(math.isfinite(value) for value in (timestamp, latitude, longitude, accuracy)):
                raise ValueError
            if timestamp <= 0 or not timestamp.is_integer():
                raise ValueError
            if not (-90 <= latitude <= 90 and -180 <= longitude <= 180 and accuracy >= 0):
                raise ValueError
            point = Point(int(timestamp), latitude, longitude, accuracy)
        except (KeyError, TypeError, ValueError, OverflowError):
            self.status = 'invalid'
            return
        if point.timestamp > now + 60:
            self.status = 'future'
            return
        if point.timestamp < self.high_water:
            self.status = 'out_of_order'
            return
        if point.timestamp > self.high_water:
            try:
                await self.save(point.timestamp)
            except Exception:
                self.status = 'error'
                return
            self.high_water = point.timestamp
            self.point = point
        elif self.point is None:
            self.point = point
        self.status = 'stale' if now - self.point.timestamp > self.stale_seconds else 'fresh'


async def fetch_latest(session, url, api_key, *, now):
    """One page, one point; never follow redirects with the account credential."""
    async with session.get(
        url + '/api/v1/points',
        headers={'Authorization': 'Bearer ' + api_key, 'Accept': 'application/json'},
        params={'order': 'desc', 'per_page': '1', 'end_at': str(int(now))},
        allow_redirects=False,
        timeout=10,
    ) as response:
        if response.status != 200:
            raise ValueError('location response rejected')
        body = bytearray()
        async for chunk in response.content.iter_chunked(4096):
            body.extend(chunk)
            if len(body) > 65536:
                raise ValueError('location response rejected')
        return json.loads(body)


def receive_only_data(entry_id, data, selected_entry):
    """Disable only the selected entry's outbound location listener."""
    if entry_id == selected_entry and data.get('mobile_app') is not None:
        return {**data, 'mobile_app': None}
    return data
