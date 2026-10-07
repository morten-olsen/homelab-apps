# mission-control

The Mission Control server (one replica, SQLite on one claim) at `https://mission-control.olsen.cloud`,
private gateway only, with Mission Control's own login (no Authentik client). Agents run as pods in
`mission-control-agents`. Design: ADR 0021 and `docs/spec/kubernetes-runner.md` in the Mission Control repository.

The folder is `.disabled`, so the ApplicationSet ignores it. **Nothing runs from it until it is renamed.**

## The Secret Morten creates (not in Git)

`mission-control-keys` in namespace **`prod`** (where the ApplicationSet deploys the release), with exactly two keys,
named like the variables the server reads. Both keys must be the laptop's, or stored secrets become unreadable.
Follow "Before you start" in the Mission Control guide `move-to-another-machine` (`--from-file`, so values stay out of
shell history and `ps`), but in `prod`, not `mission-control`:

```bash
kubectl create secret generic mission-control-keys -n prod --from-file="$KEYS"   # $KEYS holds files MC_SERVER_SECRET_KEY and MC_SERVER_JWT_SECRET
```

The forge token is entered in the web app after the first start; the chart holds none.

## Before it is enabled

1. The `apps` AppProject must allow the destination namespace `mission-control-agents` (today only `prod`).
2. `agentImage` set to a digest-pinned reference. The chart refuses to render without it.
3. The Secret above exists, and the data is copied into the claim (the migration runbook).
4. The decisions and cluster checks of the pull request (secrets encryption, `podPidsLimit`, mesh policy, CNI).

Then `git mv mission-control.disabled mission-control`.

## Test

`tests/render.sh` renders the chart and asserts the design (needs `helm`, `yq`, `jq`). Extra arguments go to `helm template`.
