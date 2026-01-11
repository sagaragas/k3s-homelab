# Ragas Homelab Documentation

Welcome to the comprehensive documentation for the Ragas Homelab Kubernetes cluster.

## Quick Links

| Resource | URL | Description |
|----------|-----|-------------|
| Homepage | https://home.ragas.cc | Service dashboard |
| Grafana | https://grafana.ragas.cc | Monitoring & metrics |
| Prometheus | https://prometheus.ragas.cc | Metrics & alerting |
| Alertmanager | https://alertmanager.ragas.cc | Alert routing |
| Docs | https://docs.ragas.cc | This documentation |

## Architecture Overview

- **Platform**: Talos Linux v1.12.1
- **Kubernetes**: v1.34.2
- **GitOps**: Flux v2
- **CNI**: Cilium (eBPF, DSR mode)
- **Ingress**: Envoy Gateway (Gateway API)
- **DNS**: bind9 + AdGuard (internal) + Cloudflare (public)
- **Storage**: Ceph CSI (RBD + CephFS) + NFS (media/backups)
- **Certificates**: cert-manager + Let's Encrypt
- **CI/CD**: GitHub Actions + Droid AI automation

## Cluster Nodes

| Node | Role | IP | Host | VMID |
|------|------|-----|------|------|
| talos-cp-1 | Control Plane | 172.16.1.50 | pve1 | 500 |
| talos-cp-2 | Control Plane | 172.16.1.51 | pve2 | 501 |
| talos-cp-3 | Control Plane | 172.16.1.52 | pve4 | 502 |
| talos-worker-1 | Worker | 172.16.1.53 | pve1 | 510 |
| talos-worker-2 | Worker | 172.16.1.54 | pve2 | 511 |
| talos-worker-3 | Worker | 172.16.1.55 | pve3 | 512 |
| talos-worker-4 | Worker | 172.16.1.56 | pve4 | 513 |

**Cluster VIP**: 172.16.1.49

## Storage

| Storage | Use | Notes |
|---------|-----|-------|
| **ceph-block (RBD)** | Databases/monitoring | RWO |
| **ceph-filesystem (CephFS)** | App configs | RWX |
| **NFS** | Media + backups | NAS-backed |

**Backend**: Proxmox Ceph cluster + NAS NFS

## Documentation Sections

### [Architecture](./architecture/)
- [Cluster Design](./architecture/cluster-design.md)
- [Network Architecture](./architecture/networking.md)
- [Storage](./architecture/storage.md)
- [Security](./architecture/security.md)
- [CI/CD Pipeline](./architecture/ci-cd.md)

### [Services](./services/)
- [Homepage Dashboard](./services/homepage.md)
- [Monitoring Stack](./services/monitoring.md)
- [Certificate Management](./services/cert-manager.md)
- [DNS & Ingress](./services/networking.md)

### [Guides](./guides/)
- [Deploying a New Service](./guides/deploy-service.md)
- [Image Automation](./guides/image-automation.md)
- [Adding a New Node](./guides/add-node.md)
- [Backup & Restore](./guides/backup-restore.md)
- [Upgrading Talos](./guides/upgrade-talos.md)
- [Upgrading Kubernetes](./guides/upgrade-kubernetes.md)

### [Runbooks](./runbooks/)
- [Node Failure](./runbooks/node-failure.md)
- [Certificate Issues](./runbooks/certificate-issues.md)
- [Storage Problems](./runbooks/storage-problems.md)
- [Network Troubleshooting](./runbooks/network-troubleshooting.md)

## Repository Structure

```
k3s-homelab/
├── .github/
│   └── workflows/          # CI/CD workflows
│       ├── validate.yaml   # YAML lint, Kubeconform, Flux Local
│       ├── droid-review.yaml  # AI code review
│       ├── droid-fix.yaml  # AI CI auto-fix
│       └── auto-merge.yaml # Auto-merge dependency PRs
├── docs/                   # This documentation
├── kubernetes/
│   ├── apps/               # Application deployments
│   │   ├── cert-manager/   # TLS certificates
│   │   ├── default/        # Default namespace apps
│   │   ├── flux-system/    # GitOps + image automation
│   │   ├── kube-system/    # Core cluster services
│   │   ├── monitoring/     # Prometheus, Grafana, Alertmanager
│   │   ├── network/        # Envoy Gateway, k8s-gateway
│   │   └── storage/        # Ceph CSI driver
│   ├── components/         # Shared Kustomize components
│   └── flux/               # Flux bootstrap configuration
├── talos/                  # Talos machine configs
└── scripts/                # Helper scripts
```

## Getting Started

1. **Access the cluster**:
   ```bash
   export KUBECONFIG=/path/to/kubeconfig
   kubectl get nodes
   ```

2. **View running services**:
   ```bash
   kubectl get pods -A
   flux get ks -A
   ```

3. **Deploy a change**:
   ```bash
   git add -A
   git commit -m "feat: add new service"
   git push
   # Flux will automatically reconcile
   ```

## Support

- **Repository**: https://github.com/sagaragas/k3s-homelab
- **Infrastructure**: https://github.com/sagaragas/homelab-iac
