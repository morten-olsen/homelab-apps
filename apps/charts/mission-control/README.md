# mission-control

The Mission Control server (one replica, SQLite on one claim) at `https://mission-control.olsen.cloud`,
private gateway only, with Mission Control's own login (no Authentik client). Agents run as pods in
`mission-control-agents`. Design: ADR 0021 and `docs/spec/kubernetes-runner.md` in the Mission Control repository.

Enabled on 2026-10-07: the ApplicationSet `homelab-apps` deploys it to `prod` as Application `mission-control`.

## The keys Secret (generated, not in Git)

`mission-control-keys` in namespace `prod` holds `MC_SERVER_SECRET_KEY` and `MC_SERVER_JWT_SECRET`. External Secrets
generates them once (`templates/keys.yaml`, refresh `0`) and the Secret is orphaned from the ExternalSecret, so
pruning or reverting the chart leaves it. Never delete it: what the server encrypted with it becomes unreadable.
A copied database keeps these keys: its secrets are re-encrypted to them with `mission-control secrets rekey
--from-key <the old key>`, run against the volume while the server is scaled to zero (the migration runbook).

The forge token is entered in the web app after the first start; the chart holds none.

## Before it was enabled

1. The `apps` AppProject allows the destination namespace `mission-control-agents` (done 2026-10-07). It comes from
   `apps/root`, the hand-installed `argocd-apps` release: a change there needs `helm upgrade argocd-apps ./apps/root -n argocd`.
2. `agentImage` and `image.tag` are pinned by digest (0.6.3 today); bump both together. The chart refuses to render an agent image without a digest.
3. The decisions and cluster checks of the pull request (secrets encryption, `podPidsLimit`, mesh policy, CNI).

It was enabled with `git mv mission-control.disabled mission-control`. The first start is an empty instance; the laptop's data is
copied in later (the migration runbook).

## After the first start: the agents' claim

Agent pods mount the server's data claim, but a claim belongs to one namespace. `templates/agents-data.yaml` adds a
volume on the host directory of the server's volume, and a claim of the same name in `mission-control-agents`. The
directory exists only once local-path has provisioned the server's claim, so:

1. Read it: `kubectl get pv "$(kubectl -n prod get pvc mission-control-data -o jsonpath='{.spec.volumeName}')" -o jsonpath='{.spec.local.path}'` (local-path makes `local` volumes)
2. Keep the server's volume on deletion of its claim (local-path's default is Delete):
   `kubectl patch pv <that volume> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`
3. Set `agents.dataPath` to the path in a pull request. Until then agent pods cannot start (their claim is missing).

If the server's claim is ever recreated, its directory changes and `agents.dataPath` must follow.

## Network

The server has no sidecar, so the mesh's `ns-isolation` does not guard it; `templates/server-network-policy.yaml`
admits only agent pods, the ingress gateway and the blackbox probe, on 7420.

## Test

`tests/render.sh` renders the chart and asserts the design (needs `helm`, `yq`, `jq`). Extra arguments go to `helm template`.

## Cluster access for roles

`agents.clusterAccess` maps Mission Control roles to service accounts in the agents namespace (`MC_K8S_ROLE_ACCESS`):
the Software Engineer runs as `mission-control-operator` (bound to `cluster-admin`: it operates the homelab like
Morten, trusted until there is a reason not to), every other Home IT role as `mission-control-cluster-read`
(get/list/watch; no Secrets, ConfigMaps, logs or exec). Mapped pods may also reach the API server and the private
gateway (Forgejo, Woodpecker); a role that is not mapped reaches neither, so it cannot clone from the forge. A new
role needs adding here. To take access back, remove the role from `roles`.

## Home network for agents

Agent pods reach the internet but none of the private ranges (`agents.egressExcept`). `agents.lan` lists the home
network subnets every agent pod may reach as well, on any port (`allow-lan`), so roles can manage the hosts and
devices there: today 192.168.10.0/24, 192.168.20.0/24 (with the homelab host) and 192.168.30.0/24. Empty it to take
the access back. Choosing subnets per role in Mission Control is planned (task 74527fd7).

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
