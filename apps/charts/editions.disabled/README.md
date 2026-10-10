# Editions recovery preparation

This chart stays disabled and pins the fixed image built by Editions main
pipeline 46, OCI revision 1b1847056ef53c3ad6ca18c5c16d27a7e4a559e1,
digest sha256:36445f586d8c6f9fc189e2c5aae5c17cd69e6340c76c0fce0b078872539718b2.
Do not rename it to enable until Morten approves the exposure choice and
validators review that exact rollout revision. Exact-image scan completed with
Trivy 0.75.0: 10 critical / 338 high findings (occurrences, not unique CVEs),
zero secret findings. See image-assessment.json for sanitized high/critical
package evidence. Reachability and disposition are pending Security assessment;
this image is not declared clean and no risk is accepted.

The workload is limited to 1536 MiB memory / two CPUs, requesting 512 MiB / 250m,
with a 256 MiB Node heap ceiling. Model-worker warm-up measured about 500 MB RSS;
these bounds are provisional until the documented 72-hour observation passes.
The acceptance and abort criteria live in the Editions repository at
`docs/operations/editions-memory.md` (PR #11).

The root `chown` initializer has been removed. The application runs as UID/GID
1001 with fsGroup 1001 and OnRootMismatch, no privilege escalation, all
capabilities dropped and RuntimeDefault seccomp. The live PV reports
spec.local.path (not spec.hostPath); its provisioner is rancher.io/local-path.
Existing directory ownership and database write permissions are unverified;
fsGroup in the Pod is not evidence that this particular mount is writable.
Before starting the 72-hour clock, verify the fixed-image Pod is Running,
startup has no EACCES/permission error, and a normal application operation
successfully writes the database. Reading the database alone is insufficient.
If the existing volume cannot be written during startup, stop and report;
do not introduce a root initializer or maintenance permission job as a fallback.
No PVC/PV deletion or database migration is part of this change.

Observation must read restartCount and lastState, and node Ready history, in
addition to continuous RSS data. Missed checks are unverified. Two failed analysis
jobs require stop/report; score coverage and invalid-vector counts determine
recovery, never analysed timestamps alone.

The pinned common chart lacks pod security and token controls, so the local
template augments its rendered Deployment and delegates all other resources to
common.all. Kubernetes API token mounting and Istio injection are disabled.
Live inspection found no PeerAuthentication anywhere in the cluster and no
Editions DestinationRule in prod, but prod has AuthorizationPolicy ns-isolation.
Without a sidecar that policy is not enforced on Editions; this is an unresolved
rollout blocker. Enabling mesh injection in a Pod dry-run adds root istio-init
with NET_ADMIN/NET_RAW plus a native istio-proxy sidecar and istio-ca token
projection. Do not enable either candidate until isolation and admission choices
are designed and reviewed; no new firewall policy or privilege waiver is approved. Gateways remain unchanged while
the chart is disabled, pending Morten's public-exposure decision.

Validation: tests/render.sh, helm lint with apps/root globals, full server-side
apply dry-run and Pod admission dry-run. Admission on 2026-10-10 yielded exactly
one container (editions), zero init containers and zero projected-token volumes;
only editions-data mounts at /data. UID/GID1001, drop ALL, no escalation,
RuntimeDefault, the explicit limits and NODE_OPTIONS remained intact. No PSA
warning was emitted. The admission check was repeated with the fixed digest
and created no live workload; repeat with the final exposure/enable revision.

Rollback disables the chart through Git and confirms workload removal while
prod/editions-data remains Bound to pvc-3aee7126-144a-4c58-b91d-caa06b42b6d0.
Argo Delete=false protects its PVC from Argo deletion; the PV reclaimPolicy is
Delete, so direct PVC deletion would destroy data. Never restore the old image.
