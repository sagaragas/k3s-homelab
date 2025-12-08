# Storage Architecture

## Overview

The cluster uses multiple storage backends for different use cases.

## Storage Classes

| Storage Class | Backend | Use Case |
|---------------|---------|----------|
| ceph-rbd | Ceph RBD | Default block storage |
| cephfs | CephFS | Shared filesystem |
| local-path | Local disk | Node-local storage |

## Ceph Storage

### Ceph Cluster

The Proxmox cluster runs Ceph with OSDs on 3 nodes:

| Node | OSD | Disk |
|------|-----|------|
| pve1 | osd.0 | NVMe |
| pve2 | osd.1 | NVMe |
| pve3 | osd.2 | NVMe |

### Ceph Pools

| Pool | Type | Replication |
|------|------|-------------|
| vm-storage | RBD | 2 |
| cephfs-data | CephFS | 2 |
| cephfs-metadata | CephFS | 2 |

## Using Persistent Volumes

### Basic PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  # storageClassName: ceph-rbd  # Default
```

### Shared Storage (RWX)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cephfs
  resources:
    requests:
      storage: 100Gi
```

## NFS Mounts

For media storage, containers mount NFS from the NAS:

```yaml
volumes:
  - name: media
    nfs:
      server: 172.16.1.250
      path: /volume2/hulk/media
```

## Backup Strategy

### Velero (Planned)

Velero will back up:
- Kubernetes resources (YAML)
- Persistent Volumes (snapshots)

### Manual Backup

```bash
# Export all resources
kubectl get all -A -o yaml > cluster-backup.yaml

# Backup etcd
talosctl -n 172.16.1.50 etcd snapshot db.snapshot
```

## Storage Recommendations

| Workload | Storage Class | Access Mode |
|----------|---------------|-------------|
| Databases | ceph-rbd | RWO |
| Prometheus | ceph-rbd | RWO |
| Shared configs | cephfs | RWX |
| Media files | NFS | RWX |
| Temporary | emptyDir | - |

## Troubleshooting

### PVC Stuck Pending

```bash
# Check storage class
kubectl get sc

# Check PVC events
kubectl describe pvc <name>

# Check Ceph health
ssh root@172.16.1.2 "ceph status"
```

### Slow Storage Performance

```bash
# Check Ceph status
ssh root@172.16.1.2 "ceph osd pool stats"

# Check for slow requests
ssh root@172.16.1.2 "ceph health detail"
```
