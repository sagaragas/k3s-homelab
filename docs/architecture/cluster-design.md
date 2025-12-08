# Cluster Design

## Overview

The Ragas Homelab runs a production-grade Kubernetes cluster using Talos Linux, an immutable, API-managed operating system designed specifically for Kubernetes.

## Why Talos Linux?

| Feature | Talos | Traditional Linux |
|---------|-------|-------------------|
| SSH Access | None (API only) | Full shell access |
| Package Manager | None | apt/yum/etc |
| Configuration | Declarative YAML | Manual/Ansible |
| Updates | Atomic, rollback-able | In-place, risky |
| Attack Surface | Minimal | Large |
| Maintenance | GitOps friendly | Requires access |

## Cluster Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              Internet                    │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │         Cloudflare (DNS/CDN)            │
                    │         ragas.cc                         │
                    └─────────────────┬───────────────────────┘
                                      │ (Optional tunnel)
┌─────────────────────────────────────▼─────────────────────────────────────────┐
│                            Home Network (172.16.1.0/24)                        │
│                                                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Router     │  │   AdGuard    │  │  Technitium  │  │    NAS       │       │
│  │ 172.16.1.1   │  │ 172.16.1.11  │  │ 172.16.1.10  │  │ 172.16.1.250 │       │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                                                │
│  ┌────────────────────────────────────────────────────────────────────────┐   │
│  │                    Kubernetes Cluster (Talos)                           │   │
│  │                         VIP: 172.16.1.49                                │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │   │
│  │  │ talos-cp-1  │  │ talos-cp-2  │  │ talos-cp-3  │  │talos-worker │    │   │
│  │  │ .50 (pve1)  │  │ .51 (pve1)  │  │ .52 (pve2)  │  │ .53 (pve2)  │    │   │
│  │  │ Control     │  │ Control     │  │ Control     │  │ Worker      │    │   │
│  │  │ Plane       │  │ Plane       │  │ Plane       │  │             │    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │   │
│  │                                                                         │   │
│  │  Load Balancer IPs (Cilium):                                           │   │
│  │  - 172.16.1.49: Kubernetes API (VIP)                                   │   │
│  │  - 172.16.1.60: k8s_gateway (internal DNS)                             │   │
│  │  - 172.16.1.61: envoy-internal (internal ingress)                      │   │
│  │  - 172.16.1.62: envoy-external (external ingress)                      │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
│                                                                                │
│  ┌────────────────────────────────────────────────────────────────────────┐   │
│  │                         Proxmox Cluster                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │   │
│  │  │    pve1     │  │    pve2     │  │    pve3     │  │    pve4     │    │   │
│  │  │ 172.16.1.2  │  │ 172.16.1.3  │  │ 172.16.1.4  │  │ 172.16.1.5  │    │   │
│  │  │ Ryzen 9    │  │ Ryzen 9     │  │ Intel N150  │  │ i5-12500T   │    │   │
│  │  │ 28GB RAM   │  │ 28GB RAM    │  │ 16GB RAM    │  │ 64GB RAM    │    │   │
│  │  │ Ceph OSD   │  │ Ceph OSD    │  │ Ceph OSD    │  │ GPU (770)   │    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────────┘
```

## High Availability

### Control Plane HA
- 3 control plane nodes across 2 physical hosts
- etcd runs on all control plane nodes
- Virtual IP (172.16.1.49) for API server access
- Any control plane node can be lost without cluster impact

### Worker Availability
- Currently 1 worker node
- All control plane nodes can also run workloads
- Can scale by adding more workers

## Resource Allocation

### Control Plane Nodes (each)
- **CPU**: 4 cores
- **Memory**: 8GB
- **Disk**: 100GB (vm-storage/Ceph RBD)
- **Network**: 1Gbps

### Worker Nodes (each)
- **CPU**: 8 cores
- **Memory**: 16GB
- **Disk**: 200GB (vm-storage/Ceph RBD)
- **Network**: 1Gbps

## Talos Configuration

### Machine Config Structure
```
talos/
├── talconfig.yaml          # Talhelper configuration
├── talenv.yaml             # Version pinning
├── talsecret.sops.yaml     # Encrypted secrets
├── clusterconfig/          # Generated configs (gitignored)
│   ├── talosconfig         # Admin config
│   └── kubernetes-*.yaml   # Per-node configs
└── patches/
    ├── controller/         # Control plane patches
    └── global/             # All-node patches
```

### Key Talos Features Used
- **Cilium CNI**: eBPF-based networking
- **KubePrism**: Local API server load balancing
- **Disk encryption**: TPM-based (optional)
- **Secure boot**: UEFI with measured boot

## Deployment Model

All changes follow GitOps principles:

```
Developer → Git Push → GitHub → Flux Reconciliation → Kubernetes
                                        ↓
                              HelmRelease/Kustomization
                                        ↓
                                   Deployed Pods
```

## Disaster Recovery

### Backup Strategy
- etcd snapshots via Talos API
- Velero for application backups
- Git repository is source of truth

### Recovery Procedures
1. **Single node failure**: Automatic recovery
2. **Quorum loss**: Restore from etcd snapshot
3. **Full cluster loss**: Rebuild from Git + backups

## Security Model

- No SSH access to nodes
- All management via Talos API (mTLS)
- RBAC for Kubernetes access
- Network policies via Cilium
- Secrets encrypted with SOPS/Age
