# Ragas Homelab Documentation

Welcome to the comprehensive documentation for the Ragas Homelab Kubernetes cluster.

## Quick Links

| Resource | URL | Description |
|----------|-----|-------------|
| Kubernetes Dashboard | https://k8s.ragas.cc | Cluster management |
| Homepage | https://home.ragas.cc | Service dashboard |
| Grafana | https://grafana.ragas.cc | Monitoring & metrics |
| Docs | https://docs.ragas.cc | This documentation |

## Architecture Overview

- **Platform**: Talos Linux v1.11.5
- **Kubernetes**: v1.34.2
- **GitOps**: Flux v2.7.5
- **CNI**: Cilium (eBPF, DSR mode)
- **Ingress**: Envoy Gateway (Gateway API)
- **Certificates**: cert-manager + Let's Encrypt

## Cluster Nodes

| Node | Role | IP | Resources |
|------|------|-----|-----------|
| talos-cp-1 | Control Plane | 172.16.1.50 | 4 CPU, 8GB RAM, 100GB |
| talos-cp-2 | Control Plane | 172.16.1.51 | 4 CPU, 8GB RAM, 100GB |
| talos-cp-3 | Control Plane | 172.16.1.52 | 4 CPU, 8GB RAM, 100GB |
| talos-worker-1 | Worker | 172.16.1.53 | 8 CPU, 16GB RAM, 200GB |

**Cluster VIP**: 172.16.1.49

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
├── docs/                    # This documentation
├── kubernetes/
│   ├── apps/               # Application deployments
│   │   ├── cert-manager/   # TLS certificates
│   │   ├── default/        # Default namespace apps
│   │   ├── flux-system/    # GitOps components
│   │   ├── kube-system/    # Core cluster services
│   │   ├── monitoring/     # Prometheus, Grafana
│   │   └── network/        # Ingress, DNS
│   ├── components/         # Shared Kustomize components
│   └── flux/              # Flux configuration
├── talos/                  # Talos machine configs
├── bootstrap/              # Initial cluster setup
└── templates/              # Config generation templates
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
