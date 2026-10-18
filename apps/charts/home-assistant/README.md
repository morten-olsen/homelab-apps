# Home Assistant

## Dawarich location

Phone → Dawarich → the existing HA Dawarich config entry →
`device_tracker.dawarich_morten` → the existing `person.morten`.
The standard HA GPS tracker computes zones using the original coordinates and
accuracy. Arrival/departure latency needs an observed real movement; polling alone
only bounds the bridge's contribution to about 30 seconds plus request time.

`files/dawarich` extends the installed AlbinLind Dawarich integration **1.0.0**
(MIT, license retained). `__init__.py` is the installed upstream entrypoint with three
changes: forward the device_tracker platform, and set `mobile_app` to null only
for the configured entry, before setting up its sensors; start optional statistics
refreshes in background tasks so an API outage cannot block the GPS tracker and
restored alert clock. Statistics and other
Dawarich entries retain their existing behavior. `sensor.py` is the installed upstream sensor platform plus one append of the
shared timestamp sensor. The other Python files implement the receive-only feed,
GPS entity and timestamp metadata. Read-only ConfigMap subPath mounts and a pod checksum
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
time on the available GPS entity. HA strips extra GPS attributes when that entity
is unavailable, so the always-readable diagnostic timestamp sensor
`sensor.dawarich_last_recorded_location` holds the original UTC time and alert
state independently. Unknown source time remains unknown. `gps_accuracy` retains the API's `accuracy` in metres. A point over 15
minutes old is unavailable (`location_status=stale`), with its original clock and status
retained by the timestamp sensor. Empty, invalid, future, API-failed and regressing responses are also
unavailable with fixed status strings. Existing HA person behavior ignores
unavailable trackers and may use its other associated devices; this bridge never
turns a stale phone point into a fresh arrival/departure or overwrites those
devices. A recovered API can make the same still-fresh point available again.

A tiny HA Store `dawarich_location.<entry_id>` persists only the greatest accepted
epoch and the sent/not-sent notification gate. Offline uploads older than that cannot move the tracker backwards, even
after restart. Equal timestamps can rehydrate after restart, but cannot replace
an already loaded point. No coordinates are persisted by the bridge's own store
(HA's ordinary recorder still records entity state). Failure to persist a newer
timestamp makes that update unavailable. Future points are excluded by the query;
a response more than 60 seconds ahead of the poll clock is rejected as well.

## 24-hour stale notification

Morten requested one ntfy notification if tracking has not updated for 24 hours.
`files/stale-automation.yaml` is the Git source for the single HA automation ID
`dawarich_location_stale_24h`; the chart also mounts its exact rendered JSON as
`/config/custom_components/dawarich/stale-automation.json`. Apply that object with
HA's authenticated `POST /api/config/automation/config/dawarich_location_stale_24h`
after the chart rolls out. The supported config API validates it, preserves other
automations and reloads only this ID. Future Git changes to this automation must
also be applied through this API after rollout; ArgoCD distributes the artifact
but does not write HA's application database/configuration files. Do not replace
the whole existing `automations.yaml`.

The automation checks on HA startup and every five minutes. It uses the timestamp sensor
state, never entity `last_updated` or a 24-hour `for` timer. Unknown recorded
time does not invent an age. At 24 hours it calls the existing ntfy `notify.home`
entity using `notify.send_message`, with Designer-directed fixed wording and
normal topic/priority defaults, then acknowledges successful delivery through
`dawarich.acknowledge_stale_location`. If notification delivery fails, acknowledgement
does not run and the next check retries. The sent flag persists in the bridge
store under the same lock as the high-water mark. API failures, restart and old
backlog do not rearm; a newer point within the 15-minute freshness window silently
rearms. There is no recovery message or repeated reminder. An acknowledgement
store failure can cause a retry/duplicate rather than silently losing the alert.

Rollback also removes/disables this single automation via HA's supported API;
otherwise it would reference the removed acknowledgement service. Other
notifications/automations remain intact.

## Validation and rollback

Run `mise exec -- scripts/ci/validate-charts.sh apps/charts/home-assistant`.
Run `python3 apps/charts/home-assistant/tests/ha_runtime.py` for a read-only
compatibility, real HA state-machine regression, startup and real-API probe inside the installed HA pod.
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
