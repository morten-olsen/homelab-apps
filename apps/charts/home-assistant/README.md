# Home Assistant

## Dawarich location

Phone → Dawarich → the existing HA Dawarich config entry →
`device_tracker.dawarich_morten` → the existing `person.morten`.
The standard HA GPS tracker computes zones using the original coordinates and
accuracy. Arrival/departure latency needs an observed real movement; polling alone
only bounds the bridge's contribution to about 30 seconds plus request time.

`files/dawarich` extends the installed AlbinLind Dawarich integration **1.0.0**
(MIT, license retained). `__init__.py` is the installed upstream file with two
changes: forward the device_tracker platform, and set `mobile_app` to null only
for the configured entry, before setting up its sensors. Statistics and other
Dawarich entries retain their existing behavior. The other two Python files are
the receive-only bridge. Read-only ConfigMap subPath mounts and a pod checksum
make the deployment reproducible. Review this overlay against upstream before a
HACS Dawarich upgrade; do not upgrade the underlying integration independently.
Removing the overlay exposes the original files on the config PVC again.

The existing credential stays in HA config-entry storage. It is never put in
values, a ConfigMap, a URL, an exception message or bridge logs. HTTPS certificate
verification remains enabled. `dawarich.olsen.cloud` resolves to the internal
Istio gateway in the cluster. Direct service requests from HA's host-network pod
are denied by `ns-isolation`; use the existing HTTPS route without changing that
policy. No MQTT hop, image, sidecar, credential, network policy or exposure is
added.

One serial request every 30 seconds asks `/api/v1/points` for `order=desc`,
`per_page=1`, and `end_at=<poll time>`. The API orders by **recording timestamp**,
not insertion time, and omits anomalous points by default. Redirects and non-200
responses are rejected, requests time out after 10 seconds, and response bodies
are capped at 64 KiB. There are no catch-up pages, queues or retry loops. The
bridge shares HA's existing resource budget; its additional work is one bounded
response and one point, rather than a second HA process.

`recorded_at` (UTC ISO) and `last_seen` (original epoch) retain the observation
time. `gps_accuracy` retains the API's `accuracy` in metres. A point over 15
minutes old is unavailable (`location_status=stale`), with its original metadata
retained. Empty, invalid, future, API-failed and regressing responses are also
unavailable with fixed status strings. Existing HA person behavior ignores
unavailable trackers and may use its other associated devices; this bridge never
turns a stale phone point into a fresh arrival/departure or overwrites those
devices. A recovered API can make the same still-fresh point available again.

A tiny HA Store `dawarich_location.<entry_id>` persists only the greatest accepted
epoch. Offline uploads older than that cannot move the tracker backwards, even
after restart. Equal timestamps can rehydrate after restart, but cannot replace
an already loaded point. No coordinates are persisted by the bridge's own store
(HA's ordinary recorder still records entity state). Failure to persist a newer
timestamp makes that update unavailable. Future points are excluded by the query;
a response more than 60 seconds ahead of the poll clock is rejected as well.

## Validation and rollback

Run `mise exec -- scripts/ci/validate-charts.sh apps/charts/home-assistant`.
Run `python3 apps/charts/home-assistant/tests/ha_runtime.py` for a read-only
compatibility and real-API probe inside the installed HA pod.
`tests/render.sh` runs poll/HTTP tests and verifies the rendered mounts, policy,
checksum and unchanged HA process/resource layout. Use the installed HA runtime
to verify TrackerEntity compatibility as well, and server-dry-run the rendered
chart, including CRDs.

After merge, verify the Forgejo mirror and ArgoCD revision, the mounted checksum,
HA's live GPS tracker timestamp/accuracy against the newest Dawarich point
(compare coordinates only in memory), person association, disabled outbound
forwarding, working statistics, and lack of points written back by HA. Never
print locations or credentials while collecting evidence.

Rollback is a Git revert and ArgoCD reconciliation. It restarts HA with the
original integration files. The deliberately disabled `mobile_app` field and
person association are HA configuration: a revert does not undo them. Remove the
new tracker from Morten's existing person through HA's person API/UI; if returning
to HA → Dawarich, reconfigure just the original entry's forwarding selector to
`device_tracker.pixel_9`. Do not recreate the person or restore the database.
Keep the old mobile entities and automations intact.
