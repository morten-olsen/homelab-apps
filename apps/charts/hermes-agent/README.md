# Hermes Agent

The dashboard is private-only at `https://hermes.olsen.cloud`, with Hermes'
bundled username/password provider. Password login is intentional: the operator's
client cannot use OIDC. This is a login form with session cookies, not HTTP Basic
authentication or an API bearer token; verify the client's actual login flow.
The shared account has access to this Hermes instance's configuration and data.

Username: `admin`. External Secrets generates a password and a separate persistent
session-signing key once in `prod/hermes-agent-dashboard-login`. They are injected
via Secret references, never stored in Git. The password is hashed in memory by
Hermes. No Authentik resources, OIDC env vars or insecure bypass are configured.

After deployment, retrieve the password privately (do not paste it into chat or
shared logs):

```sh
kubectl --context default -n prod get secret hermes-agent-dashboard-login \
  -o jsonpath='{.data.password}' | base64 -d
```

Ordinary reconciles and pod restarts retain both values. Deleting the
ExternalSecret also deletes its owned Secret; recreating it generates new
credentials and invalidates sessions. Deliberate credential rotation requires
separate approval and a dashboard restart to reload injected env vars.

## Upgrade and re-enable gate

The prepared upgrade moves from `v2026.8.16.2` to
[v0.23.1](https://github.com/NousResearch/hermes-agent/releases/tag/v0.23.1).
The versioned Docker Hub image is pinned by its multi-platform manifest digest,
shared by dashboard and gateway. The image retains `/opt/data`, UID/GID 10000 and
its own bootstrap; the prebuilt dashboard bundle avoids a runtime frontend build.
The obsolete `--insecure` and `HERMES_DASHBOARD_INSECURE` switches are removed.

Read the intervening [release notes](https://github.com/NousResearch/hermes-agent/releases),
especially [v0.22.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.0)
and [v0.23.0](https://github.com/NousResearch/hermes-agent/releases/tag/v0.23.0):
config and memory-provider migrations, unified gateway/session ownership and
plugin changes affect retained state. v0.22.0 also enables automatic pruning of
ended sessions inactive for 90 days by default. Decide whether to set
`sessions.auto_prune: false` in the retained config before first startup.
The image [runs config migrations during bootstrap](https://github.com/NousResearch/hermes-agent/blob/v0.23.1/docker/stage2-hook.sh);
a container image rollback alone is not a data rollback.

On 2026-11-15 the operator chose a fresh start rather than migration. With no
pods mounting it, `prod/hermes-agent-data` was deleted under explicit approval;
the reclaim-policy-Delete PV `pvc-8a87b9d9-f60d-4dbd-a340-9728d2738e33` was also
confirmed deleted. This enablement creates a new empty home; old credentials,
provider configuration and messaging connections are not carried over. No
backup or migration rehearsal of the discarded data was performed.

For future upgrades that preserve retained data, before merging to the
deployment branch:

1. Inspect retained config and database versions without exposing credentials.
   Keep both workloads stopped while taking an off-node copy of the entire home,
   including SQLite WAL/SHM files, credentials, plugins and config. Storage writes
   and backup actions require explicit approval.
2. Verify that copy and rehearse this image against an isolated restored home,
   without live messaging credentials or outbound delivery. Confirm migrations,
   session history, plugin compatibility and the chosen pruning policy before
   letting either workload open the original home.

Validate the chart with `scripts/ci/validate-charts.sh apps/charts/hermes-agent`.
Merging the directory without `.disabled` enables ApplicationSet discovery;
Argo can then start both workloads automatically.

After rollout, verify the ExternalSecret is Ready, `/api/auth/providers` offers
password login rather than OIDC, the unauthenticated dashboard requires login,
the generated password succeeds and an incorrect password fails. Confirm the
actual client's session flow, gateway health and a new backup. Chart rendering
is not an authentication or migration test; a successful backup job is not a
restore rehearsal.

If rollback is needed, stop both workloads through an approved GitOps change,
restore the verified pre-upgrade home while stopped, and restore the old image
and configuration together. Restoring files or changing live cluster state
requires separate approval. See [backup and recovery guidance](../../../docs/backups.md).
