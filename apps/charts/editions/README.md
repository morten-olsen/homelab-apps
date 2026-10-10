# Editions

Editions runs like every other app in prod: in the mesh, with its sidecar, so
the prod ns-isolation AuthorizationPolicy applies, and on the public and
private gateways as before. It was disabled on 2026-09-13 when its server grew
to ~63 GiB and starved the node (Mission Control task 8ccaff6f).

The leak is fixed in Editions (incubator/editions PR #11): a handful of
non-finite embeddings left similarity pairs that never resolved, and a full
batch of them made the similarity step loop forever. The chart pins the fixed
image (Editions main pipeline 46, revision 1b1847056ef53c3ad6ca18c5c16d27a7e4a559e1,
digest sha256:36445f586d8c6f9fc189e2c5aae5c17cd69e6340c76c0fce0b078872539718b2).

So a regression cannot take the node down again, the workload is bounded:
2560 MiB / 250m requested and 4 GiB / two CPUs at most. The container limit is
what protects the node. Two ONNX models run in its worker: bge-small embeddings
(~500 MB warm) and the bart-large-mnli classifier, 1.6 GB of fp32 weights. The
Node heap ceiling (`NODE_OPTIONS`, 1024 MiB) leaves room under the limit for
them. Both were sized too small at first on 2026-10-10: a 256 MiB heap
crash-looped the startup re-analysis, then a 1536 MiB limit was OOMKilled when
the classifier first loaded. The bounds are provisional until 72 hours of
observation pass; the criteria live in the Editions repository at
`docs/operations/editions-memory.md`.

The application runs as UID/GID 1001 (fsGroup 1001), without privilege
escalation or capabilities, and without a Kubernetes API token; the root
`chown` initializer is gone, as the data volume is already owned by 1001.

`image-assessment.json` holds the sanitized high/critical findings of a Trivy
0.75.0 scan of the pinned digest (10 critical / 338 high occurrences, no
secrets). Hardening the image is tracked on its own; it is not a gate to
running Editions.

Rollback: rename the chart back to `editions.disabled`. Argo removes the
workload and keeps `prod/editions-data` (Delete=false). The PV's reclaim policy
is Delete, so never delete the PVC by hand, and never restore the old image.

Validation: `tests/render.sh`.
