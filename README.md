<div align="center">

# 🏠 Homelab Kubernetes

### Production-grade Kubernetes on Proxmox with Talos Linux & GitOps

[![Talos](https://img.shields.io/badge/Talos-v1.11.5-orange?style=for-the-badge&logo=talos)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.34.2-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Flux](https://img.shields.io/badge/Flux-v0.36.0-5468FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io/)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [Infrastructure Layer](#infrastructure-layer)
  - [Kubernetes Cluster](#kubernetes-cluster)
  - [Networking](#networking)
  - [Storage](#storage)
- [GitOps & CI/CD](#gitops--cicd)
  - [Flux GitOps](#flux-gitops)
  - [Branch Protection](#branch-protection)
  - [Automated Testing](#automated-testing)
  - [Image Automation](#image-automation)
- [Security](#security)
- [Applications](#applications)
- [Repository Structure](#repository-structure)
- [Documentation](#documentation)

---

## Overview

This repository contains the complete Infrastructure as Code for a production-grade Kubernetes homelab. Every component is declaratively defined, version controlled, and automatically deployed via GitOps.

### Design Principles

- **Immutable Infrastructure** - Talos Linux provides an immutable, API-driven OS
- **GitOps Everything** - All changes flow through Git with full audit trail
- **Defense in Depth** - Multiple layers of security from OS to application
- **High Availability** - 3 control plane nodes with automated failover
- **Automated Operations** - Self-healing, auto-updates, auto-scaling

---

## Architecture

### Infrastructure Layer

The cluster runs on a 4-node Proxmox VE hypervisor cluster with Ceph distributed storage:

```mermaid
flowchart TB
  subgraph "Physical Infrastructure"
    direction LR
    pve1["pve1<br>Ryzen 9 6900HX<br>28GB<br>Compute+Ceph"]
    pve2["pve2<br>Ryzen 9 6900HX<br>28GB<br>Compute+Ceph"]
    pve3["pve3<br>Intel N150<br>16GB<br>Download+Ceph"]
    pve4["pve4<br>Intel i5-12500T<br>64GB<br>Media+GPU"]
  end

  ceph["Ceph Storage<br>(Distributed)"]

  pve1 --- ceph
  pve2 --- ceph
  pve3 --- ceph
  pve4 --- ceph
```

### Kubernetes Cluster

7 Talos Linux VMs (3 control plane + 4 workers) form the Kubernetes cluster:

```mermaid
flowchart TB
  subgraph "Talos Kubernetes Cluster"
    direction TB

    subgraph "Control Plane (HA)"
      direction LR
      cp1["talos-cp-1<br>172.16.1.50<br>4c / 8GB"]
      cp2["talos-cp-2<br>172.16.1.51<br>4c / 8GB"]
      cp3["talos-cp-3<br>172.16.1.52<br>4c / 8GB"]
    end

    vip["Cluster VIP<br>172.16.1.49:6443"]
    cp1 --> vip
    cp2 --> vip
    cp3 --> vip

    subgraph "Worker Nodes"
      direction LR
      w1["talos-worker-1<br>172.16.1.53<br>8c / 16GB"]
      w2["talos-worker-2<br>172.16.1.54<br>8c / 16GB"]
      w3["talos-worker-3<br>172.16.1.55<br>8c / 16GB"]
      w4["talos-worker-4<br>172.16.1.56<br>8c / 16GB"]
    end
  end
```

### Networking

Cilium provides advanced networking with eBPF:

```mermaid
flowchart TB
  subgraph "Ingress / LoadBalancers"
    direction LR
    t["External / LAN Traffic"] --> l2["Cilium L2 Announcer"] --> envoy["Envoy Gateway<br>(Gateway API)"] --> apps["Apps (Pods)"]
  end

  subgraph "DNS (ragas.cc)"
    direction LR
    q["Client DNS Query<br>*.ragas.cc"] --> adguard["AdGuard<br>172.16.1.11"] --> k8sgw["k8s-gateway<br>172.16.1.60"] --> coredns["CoreDNS<br>(Cluster)"]
  end
```

**LoadBalancer IPs:**

- `172.16.1.60` k8s-gateway (DNS)
- `172.16.1.61` envoy-internal (HTTPS)
- `172.16.1.62` envoy-external (HTTPS)

### Storage

Storage is provided by Proxmox Ceph (via Ceph CSI) plus NFS for backups/media:

| Type | Provider | Use Case |
|------|----------|----------|
| etcd | Local NVMe | Kubernetes state |
| Ephemeral | EmptyDir | Temporary data |
| Persistent (RWO) | Ceph RBD (`ceph-block`) | Databases / metrics |
| Persistent (RWX) | CephFS (`ceph-filesystem`) | App config / shared storage |
| Backups / Media | NFS (NAS) | Large, read-heavy or backup data |

---

## GitOps & CI/CD

### Flux GitOps

All cluster state is managed through Flux GitOps:

```mermaid
flowchart LR
  dev["Developer"] -->|"git push"| github["GitHub Repo"]
  github -->|"reconcile"| flux["Flux Operator"]
  flux -->|"apply"| cluster["Cluster State"]
  flux -->|"notify"| discord["Discord Webhook"]
```

**Components:**
- **Source Controller** - Watches Git repositories
- **Kustomize Controller** - Applies Kustomizations
- **Helm Controller** - Manages HelmReleases
- **Notification Controller** - Sends alerts to Discord
- **(Optional) Image Automation** - Manifests exist but are currently disabled; updates handled via Renovate/Dependabot

### Branch Protection

GitHub branch protection is enabled for `main`: changes merge via PRs, and the Validate checks must pass.

```mermaid
flowchart LR
  dev["Developer"] -->|"push"| branch["Feature branch"]
  branch --> pr["Pull request → main"]
  pr --> ci["CI (validate)"]
  ci -->|"PASS"| merge["Merge / auto-merge"]
  ci -->|"FAIL"| fix["Blocked (fix CI)"]
```

### Automated Testing

Every PR runs through comprehensive CI:

| Check | Tool | Purpose |
|-------|------|---------|
| **YAML Lint** | yamllint | Syntax and style validation |
| **Kubeconform** | kubeconform | Kubernetes schema validation |
| **Flux Local** | flux-local | Offline Flux validation |
| **Security Scan** | Trivy | Vulnerability detection |
| **Secret Scan** | Gitleaks | Credential leak prevention |

### Image Automation

Dependency and image tag updates are handled via Renovate/Dependabot. (Optional) Flux Image Automation manifests exist but are currently disabled.

```mermaid
flowchart LR
  registries["Registries / Charts"] --> bots["Renovate / Dependabot"]
  bots --> pr["PR to main"]
  pr --> ci["CI (validate)"]
  ci -->|"PASS"| merge["Merge / auto-merge"]
  merge --> flux["Flux GitOps"]
  flux --> cluster["Cluster"]
```

---

## Security

### Layers of Security

```mermaid
flowchart TB
  os["Layer 1: OS Security (Talos Linux)<br>- Immutable filesystem<br>- No SSH / shell<br>- API-only management<br>- Minimal attack surface"]
  net["Layer 2: Network Security (Cilium)<br>- eBPF-based network policies<br>- Encrypted pod-to-pod traffic (optional)<br>- L7 visibility / filtering"]
  secrets["Layer 3: Secret Management (SOPS + age)<br>- Encrypted at rest in Git<br>- Decrypted in-cluster by Flux<br>- Age key stored securely"]
  tls["Layer 4: TLS Everywhere (cert-manager)<br>- Let's Encrypt certificates<br>- Automatic renewal<br>- Wildcard certs"]
  git["Layer 5: GitHub CI / PR Workflow<br>- CI validation on push/PR<br>- Secret scanning<br>- Signed commits (optional)"]

  os --> net --> secrets --> tls --> git
```

---

## Applications

### Deployed Services

| Category | Service | URL | Description |
|----------|---------|-----|-------------|
| **Dashboard** | Homepage | [home.ragas.cc](https://home.ragas.cc) | Service dashboard with widgets |
| **Monitoring** | Grafana | [grafana.ragas.cc](https://grafana.ragas.cc) | Metrics visualization |
| **Monitoring** | Prometheus | [prometheus.ragas.cc](https://prometheus.ragas.cc) | Metrics collection |
| **Monitoring** | Alertmanager | [alertmanager.ragas.cc](https://alertmanager.ragas.cc) | Alert routing |
| **Docs** | MkDocs | [docs.ragas.cc](https://docs.ragas.cc) | This documentation |

### Core Infrastructure

| Component | Version | Purpose |
|-----------|---------|---------|
| Cilium | 1.18.4 | CNI, LoadBalancer, Network Policies |
| CoreDNS | 1.45.0 | Cluster DNS |
| cert-manager | 1.19.1 | TLS certificate management |
| Envoy Gateway | 1.6.1 | Gateway API ingress |
| Flux | 0.36.0 | GitOps operator |
| kube-prometheus-stack | 72.6.2 | Full monitoring stack |

---

## Repository Structure

```
k3s-homelab/
├── .github/
│   ├── workflows/           # GitHub Actions
│   │   ├── validate.yaml    # CI: lint, validate, test
│   │   ├── auto-merge.yaml  # Auto-merge Dependabot PRs
│   │   ├── flux-image-pr.yaml # Create PRs for image updates
│   │   ├── flux-diff.yaml   # Show Flux changes on PRs
│   │   ├── security.yaml    # Trivy + Gitleaks scanning
│   │   ├── labeler.yaml     # Auto-label PRs
│   │   └── release-drafter.yaml # Generate release notes
│   ├── dependabot.yaml      # Dependabot config
│   └── labeler.yaml         # Label rules
├── .githooks/
│   └── pre-push             # Local validation hook
├── kubernetes/
│   ├── apps/                # Application deployments
│   │   ├── cert-manager/    # TLS certificates
│   │   ├── default/         # User applications
│   │   │   ├── homepage/    # Dashboard
│   │   │   ├── mkdocs/      # Documentation
│   │   │   └── echo/        # Test app
│   │   ├── flux-system/     # GitOps components
│   │   │   ├── flux-operator/
│   │   │   ├── flux-instance/
│   │   │   ├── notifications/  # Discord alerts
│   │   │   └── image-automation/ # Auto-update images
│   │   ├── kube-system/     # Core services
│   │   │   ├── cilium/      # CNI
│   │   │   ├── coredns/     # DNS
│   │   │   ├── metrics-server/
│   │   │   ├── reloader/
│   │   │   └── spegel/      # Image cache
│   │   ├── monitoring/      # Observability
│   │   │   └── kube-prometheus-stack/
│   │   └── network/         # Ingress & DNS
│   │       ├── envoy-gateway/
│   │       └── k8s-gateway/
│   ├── components/          # Shared Kustomize components
│   │   └── sops/            # SOPS decryption
│   └── flux/                # Flux bootstrap
│       └── cluster/
├── talos/                   # Talos machine configs
│   ├── talconfig.yaml       # Cluster definition
│   ├── talsecret.sops.yaml  # Encrypted secrets
│   └── clusterconfig/       # Generated configs
├── docs/                    # MkDocs documentation
│   ├── architecture/
│   ├── services/
│   ├── guides/
│   └── runbooks/
├── scripts/
│   └── setup-hooks.sh       # Git hooks setup
├── .pre-commit-config.yaml  # Pre-commit hooks
├── .yamllint.yaml           # YAML linting rules
├── .sops.yaml               # SOPS encryption config
└── mkdocs.yml               # Documentation config
```

---

## Documentation

Comprehensive documentation is available at [docs.ragas.cc](https://docs.ragas.cc):

| Section | Description |
|---------|-------------|
| **[Architecture](docs/architecture/)** | System design, networking, storage, security, CI/CD |
| **[Services](docs/services/)** | Configuration guides for each deployed service |
| **[Guides](docs/guides/)** | How-to guides for common operations |
| **[Runbooks](docs/runbooks/)** | Incident response procedures |

---

## Acknowledgments

This project builds on the work of:

- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) - GitOps patterns
- [Talos Linux](https://www.talos.dev/) - Secure Kubernetes OS
- [Flux](https://fluxcd.io/) - GitOps toolkit
- [Cilium](https://cilium.io/) - eBPF networking

---

<div align="center">

**[Documentation](https://docs.ragas.cc)** · **[GitHub](https://github.com/sagaragas/k3s-homelab)**

</div>
