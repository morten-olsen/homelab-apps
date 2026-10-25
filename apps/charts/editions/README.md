# Editions

Editions stays in the prod mesh, with the existing sidecar, ns-isolation policy,
public/private gateways and persistent data claim.

Pinned image: `9f6e9c95@sha256:80c8049469ac71cbdef2535973d753eda1dc7932cfb337cb379a0ec2b3360d32`
(Editions main pipeline #58).

PR #15 fixes scheduled-publication starvation (HOMEIT-436): check due editions
before starting new feed refreshes, so repeatedly failing feeds cannot make
readiness active again before every publication check. Existing analysis still
holds publication. Feed HTTP 503 diagnosis remains HOMEIT-255. For this code
change, rollback can restore the previous recovered image
`c12c082b@sha256:a24a3086583f2745fe16847a02c11e9144255edcc03b8131caaf07c4dd006c26`
through GitOps; preserve all issues and the PVC.

Editions PR #12 fixes startup recovery: analyse pending articles without resetting
scores, hold scheduled editions while analysis runs, and checkpoint failures.
Jobs, inference, HTTP bodies and database pages are bounded. Only one fp32 ONNX
model is resident at a time; graph optimization and arena retention are disabled.
PR #13 bounds edition generation and prior-edition exclusions: score all
candidates in 64-row pages, retain budget-bounded metadata per source/focus and
drop embeddings. Unknown/zero durations cost one minute of the time budget, as
approved by Morten.
Production continues to use the configured similarity classifier; BART was
explicitly exercised in the local sizing run.

A production-copy startup recovered all 21,593 pending articles / 19 focuses.
Both models were exercised, including the largest stored texts: guarded peak
process RSS 2,841 MiB and sampled main heap 162 MiB. Request 3 GiB / 250m, limit
4 GiB / two CPUs, V8 heap 512 MiB. The limit protects the single node; software
bounds its own work. Measurements and remaining unverified paths are in
`incubator/editions/docs/operations/editions-memory-evidence.json`; the 72-hour
observation uses `docs/operations/editions-memory.md` there.

A second both-model/backlog run plus three corpus-wide generations peaked at
2,720 MiB RSS / 117 MiB main heap. Final generation with event-loop yielding
repeated the same selections at 277 MiB RSS / 114 MiB heap. These fit the
existing limits; production BART/full-corpus NLI remain unverified.

The application remains UID/GID/fsGroup 1001, without privilege escalation,
capabilities or a Kubernetes API token. No schema migration or exposure change.

`image-assessment.json` is the sanitized scan of the previous image, dated
2026-10-10. It is historical evidence, not a scan of the newly pinned image.
Image hardening is tracked separately; this task does not waive findings.

Rollback: rename the chart to `editions.disabled`. Argo removes the workload and
keeps `prod/editions-data` (`Delete=false`). Never delete that PVC or deploy the
old score-resetting image against recovered data.

Validation: `tests/render.sh`, Helm lint/render and server-side dry-run.
