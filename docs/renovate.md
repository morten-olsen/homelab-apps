# Renovate updates

`.woodpecker/renovate.yaml` runs the shared Renovate plugin on cron and manual
events. It opens Forgejo pull requests; it does not merge or deploy updates.
`renovate.json5` groups Docker updates and requires digest pins. Runner job images
inside Forgejo labels use a custom regex manager because they are not Kubernetes
image fields.

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
