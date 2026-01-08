# Storage Problems Runbook

This runbook covers diagnosing and resolving storage-related issues (Ceph CSI RBD + CephFS, plus NFS for backups/media only).

## Quick Diagnostics

```bash
kubectl get sc
kubectl get pvc -A
kubectl get pv
kubectl get csidrivers
kubectl get volumesnapshotclass

kubectl get pods -n storage
kubectl get pods -A | grep -E "Pending|ContainerCreating"
```

## Storage Classes (this cluster)

- `ceph-block` (default) — RBD, RWO; use for databases/block workloads
- `ceph-filesystem` — CephFS, RWX; use for shared app config/data

## Common Issues

### PVC Stuck in Pending

```bash
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get sc
```

Common causes:

1. **No default StorageClass** (and the PVC doesn't set `storageClassName`)
2. **StorageClass doesn't exist** (typo / wrong name)
3. **Ceph CSI not healthy**

```bash
kubectl get pods -n storage
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -50
```

### Pod Stuck in ContainerCreating (MountVolume errors)

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -50
```

If events mention Ceph CSI, inspect the CSI pods/logs in `storage`:

```bash
kubectl get pods -n storage
kubectl -n storage get pods --show-labels
```

### RBD volume stuck attached / VolumeAttachment stuck

```bash
kubectl get volumeattachment
kubectl describe volumeattachment <name>
```

If the node is gone and the attachment never clears, you may need to delete the `VolumeAttachment` **after** confirming the workload is not running anywhere else.

### Disk Full / PVC Resize

```bash
# Check node disk usage (Talos)
talosctl -n 172.16.1.50 df

# Resize PVC (if StorageClass allows expansion)
kubectl edit pvc <pvc-name> -n <namespace>
```

## Ceph Health

Ceph runs outside Kubernetes (on the Proxmox cluster). Check health from a node with the Ceph CLI:

```bash
ssh root@<proxmox-node> "ceph status"
ssh root@<proxmox-node> "ceph health detail"
ssh root@<proxmox-node> "ceph osd tree"
```

## NFS

NFS is used for backups/media only.

```bash
kubectl run nfs-test --rm -it --image=busybox -- sh
# Inside pod:
# mount -t nfs <nfs-server>:/path /mnt
```

!!! warning
    Avoid SQLite on NFS; it can corrupt.
