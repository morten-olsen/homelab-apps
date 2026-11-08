# Renovate updates

`.woodpecker/renovate.yaml` runs the shared Renovate plugin on cron and manual
events. It opens Forgejo pull requests; it does not merge or deploy updates.
`renovate.json5` groups Docker updates and requires digest pins. Runner job images
inside Forgejo labels use a custom regex manager because they are not Kubernetes
image fields.

## Disabled applications

Renovate ignores `**/*.disabled/**`, matching the ApplicationSet's disabled-chart
convention. Neither image pins nor chart dependencies in those directories are
updated, so the Docker group describes enabled applications rather than dormant ones.

Re-enabling an app is a manual upgrade and recovery decision. Before removing
`.disabled` on `main`, inspect any retained databases and volumes, review upstream
release notes and migration requirements since the pinned version, and plan the
backup/restore and staged upgrades needed to preserve that data. On a review
branch, rename the directory and run Renovate against that branch (or upgrade the
pins manually). Assess the resulting diff and migrations before pushing the
enablement to the deployment branch; do not enable first and wait for the next
scheduled update.

## Release notes

The Renovate plugin's `github_com_token` setting exports
`RENOVATE_GITHUB_COM_TOKEN` from the repository-scoped Woodpecker secret
`renovate_github_com_token`. Keep this a settings-only plugin step so Woodpecker
can enforce the secret's image filter; `environment` overrides are rejected.
The secret is limited to cron/manual events and the `code.olsen.cloud/ci/renovate`
image, not pull-request validation. The
initial token was copied from the operator's authenticated `gh` account; it has
broader access than necessary. Prefer a dedicated read-only GitHub token when
replacing it, and update the secret if that login token is revoked.

[Renovate requires GitHub authentication for changelogs on non-GitHub platforms](https://docs.renovatebot.com/getting-started/running/#githubcom-token-for-changelogs-and-tools).
Notes still depend on discoverable source repositories and upstream releases.
Digest-only image rebuilds may have no corresponding release notes.

## Validation and troubleshooting

That manager needs `autoReplaceStringTemplate` to reconstruct the entire
`docker://repository:tag@digest` reference. Without it, Renovate can discover an
unpinned image but cannot add its first digest, and the whole Docker group fails
with `Error updating branch: update failure` (HOMEIT-510).

`.woodpecker/renovate-config.yaml` validates the config and runs
`node scripts/tests/renovate-config.cjs` inside the pinned Renovate image. The test
calls that version's actual extraction and replacement functions, without registry
access or credentials. It checks first-time digest pins, refreshed digests,
duplicate labels, and simultaneous tag/digest updates. Keep the test image pin in
step with the scheduled plugin so the test exercises the updater used in production.

When updates stop, inspect the Renovate step log and [Dependency Dashboard](https://code.olsen.cloud/homelab/apps/issues/2),
even if Woodpecker reports success. Repository warnings can leave the job green.
Distinguish file-update failures from external registry errors: Docker Hub HTTP
429 can abort a scan before it tries any branch edits. Avoid overlapping full
manual scans; they share the home connection's anonymous registry quota.
