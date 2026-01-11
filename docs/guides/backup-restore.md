# Backup & Restore

This guide covers backup strategies for the Talos Kubernetes cluster.

## What to Backup

| Component | Method | Frequency |
|-----------|--------|-----------|
| Etcd | Talos snapshot | Daily |
| Talos version pins | Git (`talos/talenv.yaml`) | On change |
| Talos client config | Backup `~/.talos/config` | On change |
| Kubernetes manifests | Git (Flux) | On change |
| Secrets (SOPS) | Git (encrypted) | On change |
| PVCs | Velero (CSI snapshots) | Daily |

## Etcd Backup

Etcd contains all Kubernetes state. This is the most critical backup.

### Manual Snapshot

```bash
# Create snapshot from any control plane node
talosctl -n 172.16.1.50 etcd snapshot db.snapshot

# Verify snapshot
ls -la db.snapshot
```

### Automated Backup Script

Create a cron job or scheduled task:

```bash
#!/bin/bash
BACKUP_DIR="/backups/etcd"
DATE=$(date +%Y%m%d-%H%M%S)
NODES="172.16.1.50"

mkdir -p $BACKUP_DIR
talosctl -n $NODES etcd snapshot $BACKUP_DIR/etcd-$DATE.snapshot

# Keep last 7 days
find $BACKUP_DIR -name "*.snapshot" -mtime +7 -delete
```

### Restore from Etcd Snapshot

!!! danger "Destructive Operation"
    This will reset the cluster. Only use for disaster recovery.

```bash
# On each control plane node
talosctl -n 172.16.1.50 bootstrap --recover-from=./db.snapshot
```

## Talos Configuration Backup

Talos configuration is managed with `talhelper` (see `task talos:*`). The repo tracks version pins and cluster definition; per-node machine configs are generated into `talos/clusterconfig/` (gitignored).

### Critical Files

```
talos/
├── talenv.yaml             # Version pinning
├── talconfig.yaml          # Cluster definition (talhelper)
├── patches/                # Reusable patch snippets
└── clusterconfig/          # Generated machine configs (gitignored)
```

### Export machine configs (optional)

If you want an out-of-band backup of the live machine configs, export them from Talos and store them securely (do **not** commit them to Git):

```bash
talosctl -n <node-ip> get machineconfig -o yaml > /secure-backup/<node-name>.machineconfig.yaml
```

## Kubernetes State Backup

All Kubernetes manifests are in Git and managed by Flux.

### Full Restore from Git

```bash
# Clone the repository
git clone https://github.com/sagaragas/k3s-homelab.git
```

Bootstrap the cluster base components + Flux (operator/instance) using the repo bootstrap tooling (see `./scripts/bootstrap-apps.sh` and `bootstrap/helmfile.d/`).

### Secrets Recovery

Secrets are encrypted with SOPS. To decrypt:

```bash
# Set the age key
export SOPS_AGE_KEY_FILE=/path/to/age.key

# Decrypt a secret
sops -d kubernetes/apps/*/secret.sops.yaml
```

## PVC Backup with Velero

Velero is deployed in this cluster and configured to back up to an in-cluster S3-compatible store (Minio) and take CSI snapshots.

### Create Backup

```bash
# Backup a namespace
velero backup create my-backup --include-namespaces default

# Backup entire cluster
velero backup create full-backup
```

### Restore

```bash
velero restore create --from-backup my-backup
```

## Disaster Recovery Procedures

### Scenario 1: Single Node Failure

See [Node Failure Runbook](../runbooks/node-failure.md)

### Scenario 2: Complete Cluster Loss

1. **Provision new VMs** with Talos ISO
2. **Apply Talos configs** from backup
3. **Bootstrap etcd** from snapshot (or fresh if no snapshot)
4. **Install Flux** to restore workloads

```bash
# Fresh bootstrap
talosctl bootstrap -n 172.16.1.50

# Get kubeconfig
talosctl kubeconfig

# Bootstrap base apps + Flux (operator/instance)
./scripts/bootstrap-apps.sh
```

### Scenario 3: Corrupted Etcd

```bash
# Stop etcd on all control planes
talosctl -n 172.16.1.50,51,52 service etcd stop

# Restore from snapshot on first node
talosctl -n 172.16.1.50 bootstrap --recover-from=./db.snapshot

# Other nodes will rejoin automatically
```

## Backup Checklist

- [ ] Age private key stored in password manager
- [ ] Etcd snapshots automated (daily)
- [ ] Git repository has all manifests
- [ ] SOPS-encrypted secrets committed
- [ ] Tested restore procedure
- [ ] Offsite backup copy (3-2-1 rule)

## Testing Backups

Regularly test your backups:

```bash
# 1. Create test namespace
kubectl create ns backup-test

# 2. Deploy test app
kubectl -n backup-test run nginx --image=nginx

# 3. Backup
talosctl -n 172.16.1.50 etcd snapshot test-backup.snapshot

# 4. Delete and restore (in test environment only!)
```
