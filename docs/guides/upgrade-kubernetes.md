# Upgrade Kubernetes

This guide covers upgrading Kubernetes on this Talos cluster.

## Overview

This cluster is managed manually (no talhelper-generated configs; per-node machine configs are not stored in Git). Kubernetes upgrades are performed with `talosctl upgrade-k8s`.

The desired Kubernetes version is tracked in `talos/talenv.yaml` (Renovate may open PRs for this), but the upgrade itself is an operator-run maintenance action.

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

## Record the target version (recommended)

Update the pinned version in `talos/talenv.yaml`:

```yaml
# talos/talenv.yaml
kubernetesVersion: v1.34.3
```

Commit the change once the upgrade is complete (or as part of the same maintenance window).

## Upgrade Process

Run the upgrade from a workstation with `talosctl` configured.

### Dry run

```bash
talosctl -n 172.16.1.50 upgrade-k8s --to v1.34.3 --dry-run
```

### Upgrade

```bash
talosctl -n 172.16.1.50 upgrade-k8s --to v1.34.3
```

> You only need to target one control plane node; Talos will coordinate the Kubernetes control plane upgrade.

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
# v1.32 → v1.33 → v1.34
```

## Rollback

Downgrades are not recommended. If you need to recover, prefer restoring from a known-good etcd snapshot.

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
