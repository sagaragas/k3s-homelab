# Upgrade Kubernetes

This guide covers upgrading Kubernetes on your Talos cluster.

## Overview

With Talos, Kubernetes upgrades are managed through the Talos configuration. The process:

1. Update `kubernetesVersion` in talconfig.yaml
2. Regenerate machine configs
3. Apply configs to each node
4. Nodes upgrade Kubernetes components automatically

## Version Compatibility

| Talos Version | Supported Kubernetes |
|---------------|---------------------|
| v1.11.x | v1.31.x - v1.34.x |
| v1.10.x | v1.30.x - v1.33.x |

Check compatibility: [Talos Support Matrix](https://www.talos.dev/latest/introduction/support-matrix/)

## Pre-Upgrade Checklist

- [ ] Check current version: `kubectl version`
- [ ] Review [Kubernetes release notes](https://kubernetes.io/releases/)
- [ ] Review [Kubernetes deprecations](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)
- [ ] Backup etcd: `talosctl -n 172.16.1.50 etcd snapshot backup.snapshot`
- [ ] Verify cluster health: `kubectl get nodes`
- [ ] Check for deprecated APIs in your manifests

## Check for Deprecated APIs

```bash
# Install pluto
brew install FairwindsOps/tap/pluto

# Scan for deprecated APIs
pluto detect-files -d kubernetes/
pluto detect-helm -A
```

## Update Configuration

### 1. Update talconfig.yaml

```yaml
# talconfig.yaml
talosVersion: v1.11.5
kubernetesVersion: v1.35.0  # Update this
```

### 2. Regenerate Configs

```bash
talhelper genconfig
```

### 3. Commit Changes

```bash
git add -A
git commit -m "chore: upgrade Kubernetes to v1.35.0"
git push
```

## Upgrade Process

### Apply to Control Plane Nodes

Upgrade control plane nodes one at a time:

```bash
# First control plane
talosctl -n 172.16.1.50 apply-config \
  --file talos/clusterconfig/kubernetes-talos-cp-1.yaml

# Wait for API server to be ready
kubectl get nodes
talosctl -n 172.16.1.50 health

# Second control plane
talosctl -n 172.16.1.51 apply-config \
  --file talos/clusterconfig/kubernetes-talos-cp-2.yaml

# Wait and verify
talosctl -n 172.16.1.51 health

# Third control plane
talosctl -n 172.16.1.52 apply-config \
  --file talos/clusterconfig/kubernetes-talos-cp-3.yaml
```

### Apply to Worker Nodes

```bash
talosctl -n 172.16.1.53 apply-config \
  --file talos/clusterconfig/kubernetes-talos-worker-1.yaml
```

## Automated Upgrade Script

```bash
#!/bin/bash
CONFIG_DIR="talos/clusterconfig"

CONTROL_PLANES=(
  "172.16.1.50:kubernetes-talos-cp-1.yaml"
  "172.16.1.51:kubernetes-talos-cp-2.yaml"
  "172.16.1.52:kubernetes-talos-cp-3.yaml"
)

WORKERS=(
  "172.16.1.53:kubernetes-talos-worker-1.yaml"
)

echo "Upgrading control planes..."
for entry in "${CONTROL_PLANES[@]}"; do
  IFS=':' read -r node config <<< "$entry"
  echo "Applying config to $node"
  talosctl -n $node apply-config --file $CONFIG_DIR/$config
  sleep 30
  talosctl -n $node health --wait-timeout 5m
done

echo "Upgrading workers..."
for entry in "${WORKERS[@]}"; do
  IFS=':' read -r node config <<< "$entry"
  echo "Applying config to $node"
  talosctl -n $node apply-config --file $CONFIG_DIR/$config
  sleep 30
done

echo "Upgrade complete!"
kubectl version
```

## Post-Upgrade Verification

```bash
# Check Kubernetes version
kubectl version

# All nodes should show new version
kubectl get nodes

# Check all system pods
kubectl get pods -n kube-system

# Verify cluster health
talosctl -n 172.16.1.50 health

# Check component versions
kubectl get nodes -o wide
```

## Upgrade Cilium (if needed)

After Kubernetes upgrades, you may need to upgrade Cilium:

```bash
# Check Cilium compatibility
# https://docs.cilium.io/en/stable/network/kubernetes/compatibility/

# Update Cilium HelmRelease version
vim kubernetes/apps/kube-system/cilium/app/helmrelease.yaml

# Commit and push - Flux will upgrade
git add -A && git commit -m "chore: upgrade Cilium" && git push
```

## Troubleshooting

### API Server Not Starting

```bash
# Check API server logs
talosctl -n 172.16.1.50 logs kube-apiserver

# Check etcd connectivity
talosctl -n 172.16.1.50 etcd status
```

### Kubelet Issues

```bash
# Check kubelet logs
talosctl -n <node-ip> logs kubelet

# Check kubelet status
talosctl -n <node-ip> service kubelet
```

### Pods Stuck After Upgrade

```bash
# Check for pending pods
kubectl get pods -A | grep -v Running

# Check events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Restart stuck pods
kubectl delete pod <pod-name> -n <namespace>
```

### Version Skew Issues

Kubernetes supports n-2 minor version skew. If you skip versions:

```bash
# Upgrade incrementally
# v1.32 → v1.33 → v1.34 → v1.35
```

## Rollback

To rollback Kubernetes version:

1. Update `kubernetesVersion` in talconfig.yaml to previous version
2. Regenerate and apply configs
3. Or restore from etcd backup

```bash
# Quick rollback via config
vim talconfig.yaml  # Change version back
talhelper genconfig
talosctl -n <node> apply-config --file <config>
```

## Upgrade Schedule

| Type | Frequency | Notes |
|------|-----------|-------|
| Patch (x.x.X) | Monthly | Security fixes |
| Minor (x.X.0) | Quarterly | New features |
| Major (X.0.0) | Yearly | Breaking changes |

## References

- [Kubernetes Release Notes](https://kubernetes.io/releases/)
- [Kubernetes Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/)
- [Talos Kubernetes Upgrade](https://www.talos.dev/latest/kubernetes-guides/upgrading-kubernetes/)
