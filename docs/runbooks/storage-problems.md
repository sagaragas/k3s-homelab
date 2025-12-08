# Storage Problems Runbook

This runbook covers diagnosing and resolving storage-related issues.

## Quick Diagnostics

```bash
# Check PVCs
kubectl get pvc -A

# Check PVs
kubectl get pv

# Check storage classes
kubectl get sc

# Check pods with volume issues
kubectl get pods -A | grep -E "Pending|ContainerCreating"
```

## Common Issues

### PVC Stuck in Pending

**Symptoms:**
```
NAME      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
my-pvc    Pending
```

**Diagnosis:**
```bash
kubectl describe pvc my-pvc -n <namespace>
```

**Common Causes:**

1. **No StorageClass defined**
   ```bash
   # Check if default StorageClass exists
   kubectl get sc
   
   # Look for (default) marker
   ```

2. **StorageClass doesn't exist**
   ```yaml
   # PVC requesting non-existent class
   spec:
     storageClassName: ceph-block  # Does this exist?
   ```

3. **No CSI driver installed**
   ```bash
   # Check CSI drivers
   kubectl get csidrivers
   ```

**Resolution:**

For now (no Ceph CSI), disable persistence or use hostPath:

```yaml
# Option 1: Disable persistence in HelmRelease
persistence:
  enabled: false

# Option 2: Use emptyDir (non-persistent)
volumes:
  - name: data
    emptyDir: {}
```

### Pod Stuck in ContainerCreating

**Symptoms:**
```
NAME     READY   STATUS              RESTARTS   AGE
my-pod   0/1     ContainerCreating   0          5m
```

**Diagnosis:**
```bash
kubectl describe pod my-pod -n <namespace>
# Look for Events section

kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**Common Causes:**

1. **PVC not bound**
   - See "PVC Stuck in Pending" above

2. **Volume mount timeout**
   ```bash
   # Check if node can access storage
   kubectl get pod my-pod -o wide  # Get node
   ```

3. **Image pull issues** (not storage but similar symptoms)
   ```bash
   kubectl describe pod my-pod | grep -A5 "Events"
   ```

### Disk Full

**Symptoms:**
- Pods being evicted
- Write errors in application logs

**Diagnosis:**
```bash
# Check node disk usage (via Talos)
talosctl -n 172.16.1.50 df

# Check PVC usage (if metrics available)
kubectl top pvc -A  # Requires metrics
```

**Resolution:**

1. **Clean up old data**
   ```bash
   # Exec into pod and clean
   kubectl exec -it <pod> -- sh
   # Remove unnecessary files
   ```

2. **Expand PVC** (if supported)
   ```bash
   kubectl edit pvc my-pvc
   # Increase spec.resources.requests.storage
   ```

3. **Add more storage to pool**

### Slow Storage Performance

**Diagnosis:**
```bash
# Check I/O wait on nodes
talosctl -n 172.16.1.50 top

# Check storage backend
# For Ceph:
ssh root@172.16.1.2 "ceph status"
```

**Resolution:**
- Check network connectivity to storage
- Verify storage backend health
- Consider SSD vs HDD placement

## Storage Backend Specific

### Ceph (Future)

When Ceph CSI is configured:

```bash
# Check Ceph health
ssh root@<proxmox-node> "ceph health detail"

# Check pool status
ssh root@<proxmox-node> "ceph osd pool stats"

# Check OSD status
ssh root@<proxmox-node> "ceph osd tree"
```

### NFS

For NFS volumes:

```bash
# Test NFS connectivity from a pod
kubectl run nfs-test --rm -it --image=busybox -- sh
# Inside pod:
mount -t nfs <nfs-server>:/path /mnt
```

### Local Storage

For hostPath or local volumes:

```bash
# Check directory exists on node
talosctl -n <node-ip> ls /var/local-storage/

# Check permissions
talosctl -n <node-ip> stat /var/local-storage/
```

## Setting Up Storage (Future)

### Ceph CSI Installation

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ceph-csi-rbd
  namespace: ceph-system
spec:
  chart:
    spec:
      chart: ceph-csi-rbd
      sourceRef:
        kind: HelmRepository
        name: ceph-csi
  values:
    csiConfig:
      - clusterID: <ceph-cluster-id>
        monitors:
          - 172.16.1.2:6789
          - 172.16.1.3:6789
          - 172.16.1.4:6789
```

### Creating StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-block
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: <ceph-cluster-id>
  pool: kubernetes
reclaimPolicy: Delete
allowVolumeExpansion: true
```

## Monitoring Storage

### Prometheus Alerts

```yaml
- alert: PVCNearlyFull
  expr: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "PVC {{ $labels.persistentvolumeclaim }} is nearly full"
```

### Grafana Dashboard

Import dashboard ID `13639` for Kubernetes PVC monitoring.

## Recovery Procedures

### Recover Data from Failed PVC

1. **Create debug pod with same PVC**
   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: debug-pod
   spec:
     containers:
     - name: debug
       image: busybox
       command: ["/bin/sh", "-c", "sleep infinity"]
       volumeMounts:
       - name: data
         mountPath: /data
     volumes:
     - name: data
       persistentVolumeClaim:
         claimName: my-pvc
   ```

2. **Copy data out**
   ```bash
   kubectl cp debug-pod:/data ./backup/
   ```

### Force Delete Stuck PVC

```bash
# Remove finalizers
kubectl patch pvc my-pvc -p '{"metadata":{"finalizers":null}}'

# Delete
kubectl delete pvc my-pvc
```

!!! warning
    Force deleting may leave orphaned volumes on storage backend.
