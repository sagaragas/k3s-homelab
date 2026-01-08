# Backups (Velero + Minio)

The cluster uses Velero for Kubernetes backups, with an in-cluster Minio (S3-compatible) backend.

## Components

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Minio | `backup` | S3-compatible object storage for backup artifacts |
| Velero | `backup` | Backups/restores + CSI snapshots |

## How it works

- Velero stores backup metadata and artifacts in the `velero` bucket in Minio.
- Volume backups use CSI snapshots (Ceph CSI).
- A daily scheduled backup runs via the Velero HelmRelease.

## Common commands

```bash
# Back up a namespace
velero backup create my-backup --include-namespaces default

# Restore from a backup
velero restore create --from-backup my-backup

# View backups/restores
velero backup get
velero restore get
```

## Credentials

- Minio credentials: `kubernetes/apps/backup/minio/app/secret.sops.yaml` (Secret: `minio-credentials`)
- Velero credentials: `kubernetes/apps/backup/velero/app/secret.sops.yaml` (Secret: `velero-minio-credentials`)

## Files

- Minio HelmRelease: `kubernetes/apps/backup/minio/app/helmrelease.yaml`
- Velero HelmRelease: `kubernetes/apps/backup/velero/app/helmrelease.yaml`
- Backup namespace: `kubernetes/apps/backup/namespace.yaml`
