# mission-control

The Mission Control server (one replica, SQLite on one claim) at `https://mission-control.olsen.cloud`,
private gateway only, with Mission Control's own login (no Authentik client). Agents run as pods in
`mission-control-agents`. Design: ADR 0021 and `docs/spec/kubernetes-runner.md` in the Mission Control repository.

The folder is `.disabled`, so the ApplicationSet ignores it. **Nothing runs from it until it is renamed.**

## The keys Secret (generated, not in Git)

`mission-control-keys` in namespace `prod` holds `MC_SERVER_SECRET_KEY` and `MC_SERVER_JWT_SECRET`. External Secrets
generates them once (`templates/keys.yaml`, refresh `0`) and the Secret is orphaned from the ExternalSecret, so
pruning or reverting the chart leaves it. Never delete it: what the server encrypted with it becomes unreadable.
A plain copy of the laptop's database needs the laptop's keys; this empty first rollout does not (see the migration task).

The forge token is entered in the web app after the first start; the chart holds none.

## Before it is enabled

1. The `apps` AppProject must allow the destination namespace `mission-control-agents` (today only `prod`).
2. `agentImage` and `image.tag` are pinned by digest (0.6.2 today); bump both together. The chart refuses to render an agent image without a digest.
3. The data is copied into the claim (the migration runbook).
4. The decisions and cluster checks of the pull request (secrets encryption, `podPidsLimit`, mesh policy, CNI).

Then `git mv mission-control.disabled mission-control`.

## Test

`tests/render.sh` renders the chart and asserts the design (needs `helm`, `yq`, `jq`). Extra arguments go to `helm template`.
