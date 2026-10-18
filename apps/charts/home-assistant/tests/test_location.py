"""Observable poll-cycle behavior; coordinates are synthetic fixtures."""
import importlib.util
from pathlib import Path
import sys
import unittest

spec = importlib.util.spec_from_file_location('location', Path(__file__).parents[1] / 'files/dawarich/location.py')
location = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = location
spec.loader.exec_module(location)

class FeedTests(unittest.IsolatedAsyncioTestCase):
    async def test_newest_point_preserves_measurement_time_and_accuracy(self):
        saved = []
        async def save(value): saved.append(value)
        async def fetch(): return [{'timestamp': 1000, 'latitude': '1.25', 'longitude': '2.5', 'accuracy': 8}]
        feed = location.PointFeed(save=save)
        await feed.poll(fetch, now=1010)
        self.assertTrue(feed.available)
        self.assertEqual(feed.status, 'fresh')
        self.assertEqual(feed.point.timestamp, 1000)
        self.assertEqual(feed.point.accuracy, 8)
        self.assertEqual(feed.point.latitude, 1.25)
        self.assertEqual(saved, [1000])


class SafetyTests(unittest.IsolatedAsyncioTestCase):
    async def test_offline_backlog_expires_by_recording_time_and_recovers(self):
        async def save(value): pass
        async def fetch(): return [{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': 8}]
        feed = location.PointFeed(save=save)
        await feed.poll(fetch, now=1901)
        self.assertFalse(feed.available)
        self.assertEqual(feed.status, 'stale')
        self.assertEqual(feed.point.timestamp, 1000)
        async def fresh(): return [{'timestamp': 2000, 'latitude': 1, 'longitude': 2, 'accuracy': 9}]
        await feed.poll(fresh, now=2001)
        self.assertTrue(feed.available)
        await feed.poll(fresh, now=2901)
        self.assertEqual(feed.status, 'stale')

    async def test_regression_is_rejected_across_restart_and_duplicates_do_not_move(self):
        saved = []
        async def save(value): saved.append(value)
        async def old(): return [{'timestamp': 999, 'latitude': 1, 'longitude': 2, 'accuracy': 8}]
        feed = location.PointFeed(save=save, high_water=1000)
        await feed.poll(old, now=1001)
        self.assertEqual(feed.status, 'out_of_order')
        self.assertIsNone(feed.point)
        self.assertEqual(saved, [])
        async def equal(): return [{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': 8}]
        await feed.poll(equal, now=1001)
        self.assertTrue(feed.available)
        async def duplicate(): return [{'timestamp': 1000, 'latitude': 5, 'longitude': 6, 'accuracy': 9}]
        await feed.poll(duplicate, now=1002)
        self.assertEqual(feed.point.latitude, 1)
        self.assertEqual(saved, [])

    async def test_api_failure_is_unavailable_without_exception_or_point_leak_and_recovers(self):
        async def save(value): pass
        async def good(): return [{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': 8}]
        async def bad(): raise TimeoutError('secret-token-and-location')
        feed = location.PointFeed(save=save)
        await feed.poll(good, now=1001)
        await feed.poll(bad, now=1002)
        self.assertEqual(feed.status, 'error')
        self.assertFalse(feed.available)
        self.assertEqual(feed.point.timestamp, 1000)
        await feed.poll(good, now=1003)
        self.assertTrue(feed.available)

    async def test_bad_payloads_and_future_points_never_become_locations(self):
        async def save(value): self.fail('invalid point persisted')
        cases = [
            ([], 'empty'), ({'error': 'private'}, 'invalid'),
            ([{'timestamp': 2000, 'latitude': 1, 'longitude': 2, 'accuracy': 8}], 'future'),
            ([{'timestamp': 1000, 'latitude': 91, 'longitude': 2, 'accuracy': 8}], 'invalid'),
            ([{'timestamp': 1000, 'latitude': 1, 'longitude': 181, 'accuracy': 8}], 'invalid'),
            ([{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': -1}], 'invalid'),
            ([{'timestamp': 1000, 'latitude': 'nan', 'longitude': 2, 'accuracy': 8}], 'invalid'),
            ([{'timestamp': 1000, 'latitude': 1, 'longitude': 2}], 'invalid'),
            ([{'timestamp': True, 'latitude': 1, 'longitude': 2, 'accuracy': 8}], 'invalid'),
            ([{'timestamp': 1000.5, 'latitude': 1, 'longitude': 2, 'accuracy': 8}], 'invalid'),
            ([{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': None}], 'invalid'),
            ([{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': float('inf')}], 'invalid'),
            ([{}] * 2, 'invalid'),
        ]
        for rows, expected in cases:
            with self.subTest(expected=expected, shape=type(rows).__name__):
                async def fetch(): return rows
                feed = location.PointFeed(save=save)
                await feed.poll(fetch, now=1001)
                self.assertEqual(feed.status, expected)
                self.assertFalse(feed.available)
                self.assertIsNone(feed.point)

    async def test_persistence_failure_does_not_publish_a_point(self):
        async def save(value): raise OSError('sensitive-path')
        async def fetch(): return [{'timestamp': 1000, 'latitude': 1, 'longitude': 2, 'accuracy': 8}]
        feed = location.PointFeed(save=save)
        await feed.poll(fetch, now=1001)
        self.assertEqual(feed.status, 'error')
        self.assertIsNone(feed.point)
        self.assertEqual(feed.high_water, 0)

class HttpTests(unittest.IsolatedAsyncioTestCase):
    async def test_request_is_bounded_latest_recorded_point_without_key_in_url(self):
        from unittest.mock import MagicMock, AsyncMock
        response = MagicMock(status=200)
        async def chunks(size):
            yield b'[{"timestamp":1000}]'
        response.content.iter_chunked = chunks
        session = MagicMock()
        session.get.return_value.__aenter__ = AsyncMock(return_value=response)
        data = await location.fetch_latest(session, 'https://dawarich.olsen.cloud', 'private-fixture', now=1001)
        self.assertEqual(data, [{'timestamp': 1000}])
        args, kwargs = session.get.call_args
        self.assertEqual(args, ('https://dawarich.olsen.cloud/api/v1/points',))
        self.assertEqual(kwargs['params'], {'order': 'desc', 'per_page': '1', 'end_at': '1001'})
        self.assertEqual(kwargs['headers']['Authorization'], 'Bearer private-fixture')
        self.assertFalse(kwargs['allow_redirects'])
        self.assertEqual(kwargs['timeout'], 10)

    async def test_http_error_redirect_and_oversize_are_rejected_without_body(self):
        from unittest.mock import MagicMock, AsyncMock
        for status in [302, 401, 429, 500, 200]:
            session = MagicMock()
            response = MagicMock(status=status)
            async def chunks(size):
                for _ in range(17): yield b'x' * 4096
            response.content.iter_chunked = chunks
            session.get.return_value.__aenter__ = AsyncMock(return_value=response)
            with self.subTest(status=status), self.assertRaisesRegex(ValueError, '^location response rejected$'):
                await location.fetch_latest(session, 'https://dawarich.olsen.cloud', 'private-fixture', now=1001)

class PolicyTests(unittest.TestCase):
    def test_only_selected_entry_stops_forwarding_without_touching_credentials(self):
        data = {'api_key': 'fixture-key', 'mobile_app': 'device_tracker.old', 'name': 'Existing'}
        self.assertEqual(location.receive_only_data('selected', data, 'selected'),
                         {'api_key': 'fixture-key', 'mobile_app': None, 'name': 'Existing'})
        self.assertEqual(data['mobile_app'], 'device_tracker.old')
        self.assertIs(location.receive_only_data('other', data, 'selected'), data)
        disabled = {**data, 'mobile_app': None}
        self.assertIs(location.receive_only_data('selected', disabled, 'selected'), disabled)

if __name__ == '__main__': unittest.main()
