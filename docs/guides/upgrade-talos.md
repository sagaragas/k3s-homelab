# Upgrade Talos

This guide covers upgrading Talos Linux on your cluster nodes.

## Overview

Talos upgrades are performed node-by-node. This cluster uses `talhelper` (see `task talos:*`), but you can also upgrade directly with `talosctl upgrade`. The process:

1. Downloads new Talos image
2. Writes to disk
3. Reboots node
4. Node rejoins cluster with new version

## Pre-Upgrade Checklist

- [ ] Check current version: `talosctl -n 172.16.1.50 version`
- [ ] Review [Talos release notes](https://github.com/siderolabs/talos/releases)
- [ ] Backup etcd: `talosctl -n 172.16.1.50 etcd snapshot backup.snapshot`
- [ ] Verify cluster health: `talosctl -n 172.16.1.50 health`
- [ ] Ensure all nodes are Ready: `kubectl get nodes`

## Check Available Versions

```bash
# Current version
talosctl -n 172.16.1.50 version

# Check latest release
curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | grep tag_name
```

## Record the target version (recommended)

Update the pinned version in `talos/talenv.yaml`:

```yaml
# talos/talenv.yaml
talosVersion: v1.12.1
```

Commit the change once the upgrade is complete (or as part of the same maintenance window).

## Upgrade Process

### Upgrade Workers First

Always upgrade workers before control plane nodes.

```bash
# Upgrade worker node
task talos:upgrade-node IP=172.16.1.53

# Or directly with talosctl:
talosctl -n 172.16.1.53 upgrade \
  --image ghcr.io/siderolabs/installer:v1.12.1

# Wait for node to come back
kubectl get nodes -w
```

### Upgrade Control Plane Nodes

Upgrade control plane nodes one at a time:

```bash
# Upgrade first control plane
talosctl -n 172.16.1.50 upgrade \
  --image ghcr.io/siderolabs/installer:v1.12.1

# Wait for it to rejoin
talosctl -n 172.16.1.50 health

# Upgrade second control plane
talosctl -n 172.16.1.51 upgrade \
  --image ghcr.io/siderolabs/installer:v1.12.1

# Wait and verify
talosctl -n 172.16.1.51 health

# Upgrade third control plane
talosctl -n 172.16.1.52 upgrade \
  --image ghcr.io/siderolabs/installer:v1.12.1
```

## Automated Upgrade Script

```bash
#!/bin/bash
VERSION="v1.12.1"
IMAGE="ghcr.io/siderolabs/installer:$VERSION"

WORKERS="172.16.1.53 172.16.1.54 172.16.1.55 172.16.1.56"
CONTROL_PLANES="172.16.1.50 172.16.1.51 172.16.1.52"

echo "Upgrading workers..."
for node in $WORKERS; do
  echo "Upgrading $node"
  talosctl -n $node upgrade --image $IMAGE
  sleep 60
  talosctl -n $node health --wait-timeout 5m
done

echo "Upgrading control planes..."
for node in $CONTROL_PLANES; do
  echo "Upgrading $node"
  talosctl -n $node upgrade --image $IMAGE
  sleep 60
  talosctl -n $node health --wait-timeout 5m
done

echo "Upgrade complete!"
talosctl -n 172.16.1.50 version
```

## Post-Upgrade Verification

```bash
# Check all nodes are ready
kubectl get nodes

# Verify Talos version on all nodes
talosctl -n 172.16.1.50,172.16.1.51,172.16.1.52,172.16.1.53,172.16.1.54,172.16.1.55,172.16.1.56 version

# Check cluster health
talosctl -n 172.16.1.50 health

# Verify etcd
talosctl -n 172.16.1.50 etcd status

# Check all pods running
kubectl get pods -A | grep -v Running
```

## Rollback

If an upgrade fails, you can rollback:

```bash
# Rollback to previous version
talosctl -n <node-ip> rollback
```

!!! note
    Rollback only works if the node successfully booted the new version at least once.

## Troubleshooting

### Node Stuck After Upgrade

```bash
# Check node status
talosctl -n <node-ip> dmesg | tail -50

# Check kubelet
talosctl -n <node-ip> logs kubelet

# Force reboot if needed
talosctl -n <node-ip> reboot
```

### Etcd Issues After Upgrade

```bash
# Check etcd status
talosctl -n 172.16.1.50 etcd status

# Check etcd logs
talosctl -n 172.16.1.50 logs etcd
```

### Version Mismatch

Ensure all nodes run the same Talos version:

```bash
talosctl -n 172.16.1.50,172.16.1.51,172.16.1.52,172.16.1.53,172.16.1.54,172.16.1.55,172.16.1.56 version --short
```

## Upgrade Schedule

Recommended upgrade frequency:

| Type | Frequency |
|------|-----------|
| Patch releases (x.x.X) | Monthly |
| Minor releases (x.X.0) | Quarterly |
| Major releases (X.0.0) | As needed, after testing |

## References

- [Talos Upgrade Documentation](https://www.talos.dev/latest/talos-guides/upgrading-talos/)
- [Talos Releases](https://github.com/siderolabs/talos/releases)
