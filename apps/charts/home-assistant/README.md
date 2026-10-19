# Home Assistant

## Phone location: Home Assistant → Dawarich

Home Assistant Companion on Morten's Pixel 9 is the location source.
`device_tracker.pixel_9` supplies the existing `person.morten`; the installed
HACS Dawarich integration 1.0.0 forwards that tracker to Dawarich. Dawarich is a
history destination. There is no Dawarich → HA GPS feed or polling overlay.
Morten requested this restoration on 2026-10-19 and will stop the Dawarich phone
app. A future custom phone application is separate work.

The existing HA config entry `01KQVN8547CAQH77C3T7TAHH0M` must have
`mobile_app=device_tracker.pixel_9`. Configure it through the integration's
supported reconfigure flow, preserving host, SSL/verification, name and existing
credential. Do not commit a credential or replace the config-entry store. Person
settings use HA's person API/UI, preserving identity and unrelated trackers.
These application settings live on the existing config PVC; this document records
the desired settings. The chart uses the standard common deployment and existing
image/resources/exposure without custom integration mounts.

When reverting the retired inbound bridge, remove only HA automation ID
`dawarich_location_stale_24h` through its native config API, then remove the bridge
mounts through Git and restart normally. This retires the Dawarich-specific
24-hour ntfy reminder, timestamp entity and acknowledgement service. Clean up only
the two retired entity-registry entries (`<entry_id>/location` and
`<entry_id>/last_recorded_location`) after unload. Preserve other automations,
statistics and recorded history. The retired timestamp/alert store can remain
inert; no historical data or PVC needs deleting.

Morten must enable location tracking and the required background permission in
the HA Companion app. Server configuration alone cannot enable phone sensors or
prove movement delivery. Acceptance requires a real new phone report in HA and
its matching Dawarich point; do not inject a fabricated location or replay an old
position with a new time. Report handset delivery and movement latency as
unverified until observed.

## Validation and operations

Run `mise exec -- scripts/ci/validate-charts.sh apps/charts/home-assistant` and
server-dry-run the rendered chart. `tests/render.sh` verifies absence of the
retired overlay and preservation of the existing process, config mount and
resource budget. Follow CI, Forgejo mirror, ArgoCD and the actual HA objects.
Check the selected entry, person source and forwarding sensor through HA APIs;
compare a real phone report with Dawarich only in memory, printing timestamps,
accuracy and match booleans rather than coordinates or credentials.

The base runbook `docs/home-assistant-location.md` retains the decision and rollout
evidence. Undoing this rollback requires both a Git change and explicit HA
application reconfiguration; reverting a chart does not change person settings
or the outbound selector. Keep one source direction to prevent a feedback loop.
