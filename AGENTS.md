# Homelab Kubernetes Cluster

> **Architecture:** Talos Linux + Flux GitOps (based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template))

## Cluster Overview

| Item | Value |
|------|-------|
| **OS** | Talos Linux (immutable, API-managed) |
| **GitOps** | Flux v2 |
| **CNI** | Cilium (eBPF) |
| **Ingress** | Envoy Gateway |
| **DNS** | external-dns → Cloudflare |
| **Secrets** | SOPS + age |
| **Domain** | ragas.cc |
| **Updates** | Renovate (auto PRs) |

## Nodes

| Name | IP | Role | Proxmox | Specs |
|------|-----|------|---------|-------|
| talos-cp-1 | 172.16.1.50 | controlplane | pve1 | 4c/16GB |
| talos-cp-2 | 172.16.1.51 | controlplane | pve2 | 4c/16GB |
| talos-cp-3 | 172.16.1.52 | controlplane | pve1 | 4c/16GB |
| talos-worker-1 | 172.16.1.53 | worker | pve2 | 8c/32GB |

## Directory Structure

```
.
├── kubernetes/
│   ├── apps/                 # User applications
│   │   ├── default/          # Default namespace apps
│   │   ├── media/            # Media apps (arr stack, etc.)
│   │   ├── home/             # Home automation
│   │   └── ...
│   ├── bootstrap/            # Bootstrap components (cilium, flux)
│   └── flux/                 # Flux configuration
├── talos/                    # Talos machine configurations
│   ├── clusterconfig/        # Generated node configs
│   └── talconfig.yaml        # Talhelper configuration
├── cluster.yaml              # Main cluster configuration
├── nodes.yaml                # Node definitions
└── Taskfile.yaml             # Task automation
```

## Key Tools

| Tool | Purpose |
|------|---------|
| `talosctl` | Manage Talos nodes (no SSH!) |
| `kubectl` | Kubernetes CLI |
| `flux` | GitOps CLI |
| `task` | Task runner (like make) |
| `sops` | Encrypt/decrypt secrets |
| `mise` | Dev environment manager |
| `talhelper` | Generate Talos configs |

## Common Tasks

```bash
# Task runner commands (run from repo root)
task --list                      # List all available tasks

# Talos management
task talos:generate-config       # Generate Talos configs from talconfig.yaml
task talos:apply-node IP=x.x.x.x # Apply config to a node
task talos:upgrade-node IP=x.x.x.x # Upgrade Talos on a node
task talos:upgrade-k8s           # Upgrade Kubernetes version

# Flux / GitOps
task flux:reconcile              # Force Flux to sync
flux get ks -A                   # Check Kustomization status
flux get hr -A                   # Check HelmRelease status

# Cluster health
task cluster:pods                # List all pods
cilium status                    # Check Cilium CNI status
kubectl get nodes -o wide        # Check node status
```

## Adding a New Application

1. **Create app directory:**
   ```bash
   mkdir -p kubernetes/apps/<namespace>/<app-name>
   ```

2. **Add HelmRelease:**
   ```yaml
   # kubernetes/apps/<namespace>/<app-name>/helmrelease.yaml
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: app-name
   spec:
     interval: 30m
     chart:
       spec:
         chart: app-chart
         version: "1.x.x"
         sourceRef:
           kind: HelmRepository
           name: repo-name
           namespace: flux-system
     values:
       # Your values here
   ```

3. **Add Kustomization:**
   ```yaml
   # kubernetes/apps/<namespace>/<app-name>/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - helmrelease.yaml
   ```

4. **Register in parent ks.yaml** and push to git

## Ingress Pattern (Envoy Gateway)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-name
  namespace: app-namespace
spec:
  parentRefs:
    - name: envoy-external  # or envoy-internal for private
      namespace: network
  hostnames:
    - "app.ragas.cc"
  rules:
    - backendRefs:
        - name: app-service
          port: 80
```

- `envoy-external` → Public internet via Cloudflare Tunnel
- `envoy-internal` → Private network only

## Secrets Management

```bash
# Create secret
cat > secret.sops.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
stringData:
  API_KEY: your-secret-value
EOF

# Encrypt (uses .sops.yaml rules)
sops --encrypt --in-place secret.sops.yaml

# Decrypt for viewing
sops --decrypt secret.sops.yaml
```

## Services NOT on Kubernetes

These remain on Proxmox LXC (managed in `/root/homelab/iac`):

| Service | IP | Reason |
|---------|-----|--------|
| Plex | 172.16.1.33 | GPU passthrough |
| Jellyfin | 172.16.1.30 | GPU + USB |
| qBittorrent | 172.16.1.32 | 2.5Gb NIC |
| AdGuard | 172.16.1.11 | DNS outside k8s |
| PBS | 172.16.1.12 | Proxmox service |

## Network Layout

| Resource | IP/URL |
|----------|--------|
| Talos API VIP | 172.16.1.49 |
| Kubernetes API | https://172.16.1.49:6443 |
| Internal Gateway | 172.16.1.60 |
| External Gateway | Via Cloudflare Tunnel |
| Apps | https://<app>.ragas.cc |

## Deployment Flow

```
git push → GitHub → Flux detects change → Reconciles → Apps deployed
                         ↓
              Renovate creates PRs for updates
```

## References

- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) - This cluster is based on
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops) - Reference implementation
- [Home Operations Discord](https://discord.gg/home-operations) - Community support
- [kubesearch.dev](https://kubesearch.dev/) - Search for app configs
