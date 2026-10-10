# Editions recovery preparation

This chart stays disabled and still contains the original leaking digest. Do not
rename it to enable until the fixed image is built and pinned, the exposure
choice is approved by Morten, and validators review that exact rollout revision.

The workload is limited to 1536 MiB memory / two CPUs, requesting 512 MiB / 250m,
with a 256 MiB Node heap ceiling. Model-worker warm-up measured about 500 MB RSS;
these bounds are provisional until the documented 72-hour observation passes.
The acceptance and abort criteria live in the Editions repository at
`docs/operations/editions-memory.md` (PR #11).

The root `chown` initializer has been removed. The application runs as UID/GID
1001 with fsGroup 1001 and OnRootMismatch, no privilege escalation, all
capabilities dropped and RuntimeDefault seccomp. The preserved local PV was
previously used by UID 1001; normal Kubernetes volume-group handling is used.
If the existing volume cannot be written during startup, stop and report;
do not introduce a root initializer or maintenance permission job as a fallback.
No PVC/PV deletion or database migration is part of this change.

The pinned common chart lacks pod security and token controls, so the local
template augments its rendered Deployment and delegates all other resources to
common.all. Kubernetes API token mounting and Istio injection are disabled.
Live inspection found no PeerAuthentication anywhere in the cluster and no
Editions DestinationRule in prod; fresh rollout review must confirm that this
still preserves the intended gateway access. Gateways remain unchanged while
the chart is disabled, pending Morten's public-exposure decision.

Validation: tests/render.sh, helm lint with apps/root globals, full server-side
apply dry-run and Pod admission dry-run. Admission on 2026-10-10 yielded exactly
one container (editions), zero init containers and zero projected-token volumes;
only editions-data mounts at /data. UID/GID1001, drop ALL, no escalation,
RuntimeDefault, the explicit limits and NODE_OPTIONS remained intact. No PSA
warning was emitted. The admission check used the old image for preparation
only and created no live workload; repeat with the fixed digest before enable.

Rollback disables the chart through Git and confirms workload removal while
prod/editions-data remains Bound to pvc-3aee7126-144a-4c58-b91d-caa06b42b6d0.
Argo Delete=false protects its PVC from Argo deletion; the PV reclaimPolicy is
Delete, so direct PVC deletion would destroy data. Never restore the old image.
