# App Backups

Encrypted incremental backups for app PVCs using
[Volsync](https://volsync.readthedocs.io/) with restic. The backup
infrastructure (Volsync operator, restic encryption secret, NFS target) is
provisioned by the core repo — this repo only needs to declare which PVCs should
be backed up.

## How it works

The common library (`apps/common/templates/_helpers.tpl`) includes a
`common.backup` helper that generates a Volsync `ReplicationSource` for each PVC
with `backup: true`. Apps using `common.all` get this automatically. Apps with
custom templates include it via a `backup.yaml` template.

Each ReplicationSource:
- Mounts the source PVC read-only (`copyMethod: Direct`)
- Mounts the NFS share at `/backup` via `moverVolumes`
- References the `volsync-restic` secret (auto-reflected to all namespaces)
- Runs on the configured schedule with restic encryption + deduplication

## Configuring backup for a PVC

Add `backup: true` to a PVC entry in the app's `values.yaml`:

```yaml
persistentVolumeClaims:
  - name: data
    size: 5Gi
    storageClassName: local-path
    backup: true
```

Set `backup: false` for data that can be redownloaded or regenerated (ML models,
caches, static file builds).

### Optional per-PVC overrides

```yaml
persistentVolumeClaims:
  - name: data
    size: 5Gi
    backup: true
    backupSchedule: "0 1 * * *"    # override default schedule (cron)
    backupRetain:                    # override default retention
      daily: 14
      weekly: 8
      monthly: 6
```

If omitted, `backupSchedule` and `backupRetain` fall back to the globals in
`apps/root/values.yaml` under `globals.backup.schedule` and
`globals.backup.retain`.

### Default schedule and retention

Configured in `apps/root/values.yaml`:

```yaml
globals:
  backup:
    enabled: true
    nfs:
      server: 192.168.20.106
      path: /mnt/HDD/k8s/backups
    schedule: "0 4 * * *"       # 04:00 daily
    retain:
      daily: 7
      weekly: 4
      monthly: 3
```

### Disabling app backups entirely

```yaml
# In apps/root/values.yaml
globals:
  backup:
    enabled: false
```

## Apps with custom templates

Apps that don't use `common.all` (e.g., immich, jellyfin, home-assistant) need a
`templates/backup.yaml` file:

```yaml
{{ include "common.backup" . }}
```

This is already added to: coder, forgejo, gitea, home-assistant, immich,
jellyfin, jellyfin-kids, n8n, wger, zot.

## What is NOT backed up

| App | PVC | Reason |
|-----|-----|--------|
| ollama | data | Downloadable ML models |
| immich | model-cache | Redownloaded automatically |
| tandoor | static | Regenerated on startup |
| wger | beat-schedule | Celery schedule, auto-recovered |
| External NFS volumes | movies, music, books, etc. | Backed up separately by the NAS |

## Monitoring backups

```bash
# List all backup sources and their last sync
kubectl get replicationsource -n prod

# Detailed status for a specific backup
kubectl describe replicationsource backup-vaultwarden-data -n prod
```

## Restoring an app PVC

### Via Volsync ReplicationDestination

Scale down the app first, then create a ReplicationDestination:

```bash
# Scale down the app (adjust the deployment name as needed)
kubectl scale deployment vaultwarden -n prod --replicas=0

# Restore the PVC
cat <<EOF | kubectl apply -f -
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: restore-vaultwarden-data
  namespace: prod
spec:
  trigger:
    manual: restore-once
  restic:
    repository: volsync-restic
    destinationPVC: vaultwarden-data
    copyMethod: Direct
    moverSecurityContext:
      runAsUser: 0
      runAsGroup: 0
    moverVolumes:
      - mountPath: backup
        volumeSource:
          nfs:
            server: 192.168.20.106
            path: /mnt/HDD/k8s/backups
EOF

# Wait for restore to complete
kubectl get replicationdestination restore-vaultwarden-data -n prod -w

# Clean up and scale back up
kubectl delete replicationdestination restore-vaultwarden-data -n prod
kubectl scale deployment vaultwarden -n prod --replicas=1
```

The PVC name follows the pattern `<release-name>-<pvc-name>` (e.g.,
`vaultwarden-data`, `immich-upload`, `forgejo-data`).

### Via restic CLI

For manual inspection before restoring:

```bash
export RESTIC_PASSWORD=$(kubectl get secret volsync-restic -n shared \
  -o jsonpath='{.data.RESTIC_PASSWORD}' | base64 -d)
export RESTIC_REPOSITORY=/path/to/nfs/mount

# List snapshots for a specific app
restic snapshots --host backup-vaultwarden-data

# Restore to a local directory for inspection
restic restore latest --host backup-vaultwarden-data --target /tmp/restore
```

## Disaster recovery

For full cluster DR including app PVCs, see the core repo documentation. The
restore priority for apps:

1. **Critical** — vaultwarden, forgejo/gitea, immich (upload + library)
2. **Important** — home-assistant, esphome, n8n, vikunja, signal
3. **Standard** — all remaining apps

## Backup schedule

Each app PVC gets a deterministic minute offset within the **04:00 hour** based
on the backup name length (e.g., `23 4 * * *`). This staggers backups to avoid
restic repository lock contention. Override per-PVC via `backupSchedule`.
