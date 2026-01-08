# Storage Architecture

## Overview

The cluster uses Ceph CSI to connect Kubernetes directly to the Proxmox Ceph cluster:

- **RBD** (`ceph-block`) for block volumes (RWO)
- **CephFS** (`ceph-filesystem`) for shared filesystem volumes (RWX)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ Prometheus  │  │   Grafana   │  │ Alertmanager│                 │
│  │   (50Gi)    │  │   (10Gi)    │  │    (5Gi)    │                 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │
│         │                │                │                         │
│         └────────────────┼────────────────┘                         │
│                          │                                          │
│                 ┌────────┴────────┐                                 │
│                 │  ceph-csi-rbd   │                                 │
│                 │   (CSI Driver)  │                                 │
│                 └────────┬────────┘                                 │
└──────────────────────────┼──────────────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────────┐
│                          ▼                                          │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    Proxmox Ceph Cluster                        │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐          │  │
│  │  │  pve1   │  │  pve2   │  │  pve3   │  │  pve4   │          │  │
│  │  │ MON+OSD │  │ MON+OSD │  │ MON+OSD │  │ MON+OSD │          │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘          │  │
│  │                                                               │  │
│  │  Pool: kubernetes (2x replication, 32 PGs)                   │  │
│  │  FSID: eb53e78d-4b17-4e8c-8186-cd82025a8917                  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Storage Classes

| Storage Class | Backend | Access Mode | Default |
|---------------|---------|-------------|---------|
| `ceph-block` | Ceph RBD | RWO | Yes |
| `ceph-filesystem` | CephFS | RWX | No |

## Ceph Cluster Details

### Proxmox Ceph

| Component | Details |
|-----------|---------|
| **FSID** | `eb53e78d-4b17-4e8c-8186-cd82025a8917` |
| **Monitors** | 172.16.1.2, .3, .4, .5 (port 6789) |
| **OSDs** | 5 OSDs across 4 nodes |
| **Total Capacity** | ~3.6 TiB |

### Kubernetes Pool

| Setting | Value |
|---------|-------|
| **Pool Name** | `kubernetes` |
| **PG Count** | 32 |
| **Replication** | 2x |
| **User** | `client.kubernetes` |

## Current PVCs

The largest stateful PVCs live in `monitoring` (Prometheus/Grafana/Alertmanager) on `ceph-block`. Many application config PVCs use `ceph-filesystem`.

| Namespace | PVC | Size | Workload |
|-----------|-----|------|----------|
| monitoring | prometheus-db | 50Gi | Metrics storage (7d retention) |
| monitoring | grafana | 10Gi | Dashboards & settings |
| monitoring | alertmanager-db | 5Gi | Alert state |

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
  # storageClassName: ceph-block  # Default
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
  storageClassName: ceph-filesystem
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

### Velero (Deployed)

Velero backs up:
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
| Databases | ceph-block | RWO |
| Prometheus | ceph-block | RWO |
| Shared configs | ceph-filesystem | RWX |
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
