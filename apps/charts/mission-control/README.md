# mission-control

The Mission Control server (one replica, SQLite on one claim) at `https://mission-control.olsen.cloud`,
private gateway only, with Mission Control's own login (no Authentik client). Agents are ACP servers it connects
to, such as workforce's, added in Mission Control with an endpoint and a token; it starts nothing in the cluster.
Design: ADR 0038 in the Mission Control repository.

Enabled on 2026-10-07: the ApplicationSet `homelab-apps` deploys it to `prod` as Application `mission-control`.

## The keys Secret (generated, not in Git)

`mission-control-keys` in namespace `prod` holds `MC_SERVER_SECRET_KEY` and `MC_SERVER_JWT_SECRET`. External Secrets
generates them once (`templates/keys.yaml`, refresh `0`) and the Secret is orphaned from the ExternalSecret, so
pruning or reverting the chart leaves it. Never delete it: what the server encrypted with it becomes unreadable.
A copied database keeps these keys: its secrets are re-encrypted to them with `mission-control secrets rekey
--from-key <the old key>`, run against the volume while the server is scaled to zero (the migration runbook).

The forge token is entered in the web app after the first start; the chart holds none.

## Before it was enabled

1. `image.tag` is pinned by tag and digest; the release pipeline writes it.
2. The decisions and cluster checks of the pull request (secrets encryption, mesh policy, CNI).

It was enabled with `git mv mission-control.disabled mission-control`. The first start is an empty instance; the laptop's data is
copied in later (the migration runbook).

## The cut to ACP agents (0.64.0)

0.64.0 stopped running agents (ADR 0038): the agents namespace, its accounts, rights, quota, network policies and
cleanup went from the chart, and the server started from an empty database on a new claim, `mission-control-store`
(see `values.yaml`). What that left, for a person to remove when nothing from before is wanted:

- the old claim `mission-control-data` in `prod`, kept on prune, and its volume (Retain): the old database, homes and
  runs. `kubectl -n prod delete pvc mission-control-data`, then the volume and its host directory.
- the agents' volume `mission-control-agents-data` (Retain, released when the namespace went): it points at the old
  claim's host directory and holds nothing of its own. `kubectl delete pv mission-control-agents-data`.
- the old backups at `/mnt/HDD/k8s/backups/mission-control-data` on the NAS (and their copy), no longer pruned.
- the `apps` AppProject's destination namespace `mission-control-agents`, in `apps/root` (the hand-installed
  `argocd-apps` release: `helm upgrade argocd-apps ./apps/root -n argocd`).

## Network

The server has no sidecar, so the mesh's `ns-isolation` does not guard it; `templates/server-network-policy.yaml`
admits only the ingress gateway and the blackbox probe, on 7420. It reaches agents' endpoints (for workforce,
`wss://workforce.olsen.cloud/agents/<agent>/acp`) through the private gateway, as any client does.

## Test

`tests/render.sh` renders the chart and asserts the design (needs `helm`, `yq`, `jq`). Extra arguments go to `helm template`.

## Forge webhooks

`config.forgeWebhook.enabled` wires `MC_FORGE_WEBHOOK_SECRET` from the dedicated
`mission-control-forge-webhook` Secret. External Secrets generates a 64-character password,
base64-encoded, once (`refreshInterval: "0"`); the target is immutable and orphaned. Generator resources stay declared even when hooks are disabled.
The existing encryption and JWT keys are unaffected. Disabling the option removes the
webhook environment reference only; normal polling/refresh continues.
The retained immutable key is not deleted or rotated by this rollback or re-enabling.
Intentional key replacement requires a separately approved credential rotation; do not delete the Secret. Enabling or disabling restarts
the single Recreate server briefly.

Use Forgejo's Site Administration → Webhooks → Add System Webhook (Forgejo type),
not Default Webhooks, which are copied only to newly created repositories. Target
`https://mission-control.olsen.cloud/api/hooks/forges/8c5dde3f-1af2-4e0d-afec-9da9d4a34f08`,
POST, application/json, active, TLS verification enabled, push and all pull-request event
categories (including synchronization, comments and reviews). No Authorization header.
An administrator must transfer the generated key locally into the Secret field without
printing it, storing it in Git or task comments, or sharing it with the agent. For example,
on a trusted Linux workstation with cluster access and `wl-copy`:

```sh
kubectl -n prod get secret mission-control-forge-webhook -o jsonpath='{.data.MC_FORGE_WEBHOOK_SECRET}' | base64 --decode | wl-copy
```

Paste into Forgejo, then clear the clipboard with `wl-copy --clear` (disable clipboard
history before copying). This uses the decoded Kubernetes value verbatim; do not decode
the generated password a second time. Keep the route private. Test a signed delivery
(202), then a real event for a linked open PR. Record only delivery ID, time and status.
Unsigned requests return 404; a test ping alone does not prove PR refresh. Build status
still polls the current head independently of hooks.

Forgejo v16 reference: https://forgejo.org/docs/v16.0/user/repository/webhooks/

## Probes

Readiness uses `/api/ready`, which reads one row at most from SQLite and returns 503 if the
read fails. Startup and liveness use `/api/health`, so thrown read errors remove the server
from Service endpoints without directly causing restarts. A synchronous SQLite I/O stall can
block the event loop and cause liveness timeouts and restarts; probe timeouts do not cancel SQL. This read check does not prove that
`/data` is writable. Deploy a server release containing `/api/ready` before merging this probe change.
