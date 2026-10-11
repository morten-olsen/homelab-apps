# Editions

Editions stays in the prod mesh, with the existing sidecar, ns-isolation policy,
public/private gateways and persistent data claim.

Pinned image: `6dee3a01@sha256:4c1675a39e1849272eb21dc029a49b04851eca0e4d2a07f01130cbfb04072b25`
(main pipeline #49, OCI revision verified).

Editions PR #12 fixes startup recovery: analyse pending articles without resetting
scores, hold scheduled editions while analysis runs, and checkpoint failures.
Jobs, inference, HTTP bodies and database pages are bounded. Only one fp32 ONNX
model is resident at a time; graph optimization and arena retention are disabled.
Production continues to use the configured similarity classifier; BART was
explicitly exercised in the local sizing run.

A production-copy startup recovered all 21,593 pending articles / 19 focuses.
Both models were exercised, including the largest stored texts: guarded peak
process RSS 2,841 MiB and sampled main heap 162 MiB. Request 3 GiB / 250m, limit
4 GiB / two CPUs, V8 heap 512 MiB. The limit protects the single node; software
bounds its own work. Measurements and remaining unverified paths are in
`incubator/editions/docs/operations/editions-memory-evidence.json`; the 72-hour
observation uses `docs/operations/editions-memory.md` there.

The application remains UID/GID/fsGroup 1001, without privilege escalation,
capabilities or a Kubernetes API token. No schema migration or exposure change.

`image-assessment.json` is the sanitized scan of the previous image, dated
2026-10-10. It is historical evidence, not a scan of the newly pinned image.
Image hardening is tracked separately; this task does not waive findings.

Rollback: rename the chart to `editions.disabled`. Argo removes the workload and
keeps `prod/editions-data` (`Delete=false`). Never delete that PVC or deploy the
old score-resetting image against recovered data.

Validation: `tests/render.sh`, Helm lint/render and server-side dry-run.
