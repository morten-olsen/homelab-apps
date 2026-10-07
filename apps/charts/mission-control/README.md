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
