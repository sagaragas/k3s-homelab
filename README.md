# Homelab Kubernetes Cluster

Production-grade Kubernetes cluster running on Proxmox VE with Talos Linux, managed via GitOps.

## Overview

| Component | Details |
|-----------|---------|
| **OS** | [Talos Linux](https://www.talos.dev/) v1.11.5 |
| **Kubernetes** | v1.34.2 |
| **CNI** | [Cilium](https://cilium.io/) v1.18.4 |
| **GitOps** | [Flux](https://fluxcd.io/) v0.36.0 |
| **Secrets** | [SOPS](https://github.com/getsops/sops) with Age encryption |
| **Ingress** | [Envoy Gateway](https://gateway.envoyproxy.io/) v1.6.1 |
| **Certificates** | [cert-manager](https://cert-manager.io/) v1.19.1 with Let's Encrypt |

## Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Proxmox VE Cluster                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │    pve1     │  │    pve2     │  │    pve3     │              │
│  │  (ceph)     │  │  (ceph)     │  │  (ceph)     │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│         │               │               │                       │
│  ┌──────┴───────────────┴───────────────┴──────┐                │
│  │              Talos Kubernetes               │                │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐       │                │
│  │  │ cp-1    │ │ cp-2    │ │ cp-3    │ ← HA  │                │
│  │  │ control │ │ control │ │ control │       │                │
│  │  └─────────┘ └─────────┘ └─────────┘       │                │
│  │  ┌─────────────────────────────────┐       │                │
│  │  │          worker-1               │       │                │
│  │  └─────────────────────────────────┘       │                │
│  └─────────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

### Nodes

| Node | Role | IP | Resources |
|------|------|-----|-----------|
| talos-cp-1 | Control Plane | 172.16.1.50 | 4 CPU, 8GB RAM |
| talos-cp-2 | Control Plane | 172.16.1.51 | 4 CPU, 8GB RAM |
| talos-cp-3 | Control Plane | 172.16.1.52 | 4 CPU, 8GB RAM |
| talos-worker-1 | Worker | 172.16.1.53 | 4 CPU, 16GB RAM |

**Cluster VIP**: `172.16.1.49`

## Network

| Service | IP | Purpose |
|---------|-----|---------|
| Cluster VIP | 172.16.1.49 | Kubernetes API |
| k8s-gateway | 172.16.1.60 | Split-horizon DNS |
| envoy-internal | 172.16.1.61 | Internal ingress |
| envoy-external | 172.16.1.62 | External ingress (unused) |

### DNS Configuration

Configure your DNS server (AdGuard Home, Pi-hole, etc.) to forward `*.ragas.cc` queries to `172.16.1.60`.

## Applications

### Core Infrastructure

| App | Version | Namespace | Description |
|-----|---------|-----------|-------------|
| Cilium | 1.18.4 | kube-system | CNI with L2 LoadBalancer |
| CoreDNS | 1.45.0 | kube-system | Cluster DNS |
| cert-manager | 1.19.1 | cert-manager | TLS certificate management |
| Envoy Gateway | 1.6.1 | network | Gateway API implementation |
| k8s-gateway | 3.2.8 | network | External DNS for split-horizon |
| Flux | 0.36.0 | flux-system | GitOps operator |
| Spegel | 0.5.1 | kube-system | P2P image distribution |
| Reloader | 2.2.5 | kube-system | Secret/ConfigMap reload |
| Metrics Server | 3.13.0 | kube-system | Resource metrics |

### Applications

| App | URL | Description |
|-----|-----|-------------|
| Homepage | https://home.ragas.cc | Dashboard |
| Grafana | https://grafana.ragas.cc | Monitoring dashboards |
| Prometheus | https://prometheus.ragas.cc | Metrics collection |
| Alertmanager | https://alertmanager.ragas.cc | Alert management |

## Repository Structure

```
├── docs/                    # Documentation (MkDocs)
├── kubernetes/
│   ├── apps/               # Application deployments
│   │   ├── cert-manager/   # TLS certificates
│   │   ├── default/        # User applications
│   │   ├── flux-system/    # GitOps
│   │   ├── kube-system/    # Core services
│   │   ├── monitoring/     # Prometheus stack
│   │   └── network/        # Ingress & DNS
│   ├── bootstrap/          # Initial cluster setup
│   │   ├── helmfile.yaml   # Bootstrap apps
│   │   └── talos/          # Talos configuration
│   ├── components/         # Reusable Kustomize components
│   └── flux/               # Flux configuration
├── scripts/                # Utility scripts
└── talos/                  # Generated Talos configs
```

## Quick Start

### Prerequisites

- [mise](https://mise.jdx.dev/) - Tool version manager
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [flux](https://fluxcd.io/flux/cmd/) - Flux CLI
- [talosctl](https://www.talos.dev/latest/talos-guides/install/talosctl/) - Talos CLI
- [sops](https://github.com/getsops/sops) - Secrets encryption
- [age](https://github.com/FiloSottile/age) - Encryption tool

### Install Tools

```bash
mise trust
mise install
```

### Access Cluster

```bash
export KUBECONFIG=/path/to/kubeconfig
kubectl get nodes
```

### Useful Commands

```bash
# Check Flux status
flux get ks -A
flux get hr -A

# Force reconciliation
flux reconcile ks cluster-apps --with-source

# Check Cilium
cilium status

# View logs
kubectl logs -n <namespace> <pod> -f

# Decrypt a secret
sops -d kubernetes/apps/cert-manager/cert-manager/app/secret.sops.yaml
```

## GitOps Workflow

1. Make changes to manifests in `kubernetes/apps/`
2. Commit and push to GitHub
3. Flux automatically detects changes and reconciles

```bash
# Watch reconciliation
flux get ks -A --watch

# Manual sync
flux reconcile source git flux-system
```

## Adding Applications

1. Create app directory under `kubernetes/apps/<namespace>/<app-name>/`
2. Add HelmRelease or Kustomization
3. Create `ks.yaml` for Flux Kustomization
4. Add to parent `kustomization.yaml`
5. Commit and push

See [docs/guides/deploy-service.md](docs/guides/deploy-service.md) for detailed instructions.

## TLS Certificates

All services use Let's Encrypt certificates via cert-manager with Cloudflare DNS-01 challenge.

```yaml
# Add to HTTPRoute
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
```

## Monitoring

Access Grafana at https://grafana.ragas.cc (default: admin/admin)

Pre-configured dashboards:
- Kubernetes cluster overview
- Node metrics
- Pod metrics
- Cilium networking

## Backup & Recovery

### etcd Snapshots

```bash
talosctl -n 172.16.1.50 etcd snapshot db.snapshot
```

### Flux Recovery

```bash
# Re-bootstrap from git
flux bootstrap github \
  --owner=sagaragas \
  --repository=k3s-homelab \
  --branch=main \
  --path=kubernetes/flux
```

## Documentation

Full documentation available at [docs/](docs/) or https://docs.ragas.cc

- [Architecture](docs/architecture/)
- [Services](docs/services/)
- [Guides](docs/guides/)
- [Runbooks](docs/runbooks/)

## Credits

Based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) - a battle-tested GitOps template for Talos Kubernetes.

## License

MIT
