# Homelab Kubernetes Cluster

> **Architecture:** Talos Linux + Flux GitOps (based on [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template))

## Cluster Overview

| Item | Value |
|------|-------|
| **OS** | Talos Linux (immutable, API-managed) |
| **GitOps** | Flux v2 |
| **CNI** | Cilium (eBPF) |
| **Ingress** | Envoy Gateway |
| **DNS** | bind9 (172.16.1.10) + AdGuard (172.16.1.11) |
| **External DNS** | Cloudflare (ragas.cc public) |
| **Secrets** | SOPS + age |
| **Updates** | Renovate (auto-merge patch/minor to main) |

## Domains

| Domain | Purpose | DNS Provider |
|--------|---------|--------------|
| `ragas.cc` | Internal services (K8s, LXC) | bind9 → AdGuard |
| `ragas.sh` | Public-facing services | Cloudflare |

### Public Services (ragas.sh) - DO NOT MIGRATE DOMAINS
- `request.ragas.sh` → Overseerr (public requests)
- `plex.ragas.sh` → Plex (public streaming)
- `jelly.ragas.sh` → Jellyfin (public streaming)

### Internal Services (ragas.cc)
All internal services use `*.ragas.cc` via bind9 DNS.

## Infrastructure

### Proxmox Nodes

| Name | IP | Role |
|------|-----|------|
| pve1 | 172.16.1.2 | Proxmox host |
| pve2 | 172.16.1.3 | Proxmox host |
| pve3 | 172.16.1.4 | Proxmox host |
| pve4 | 172.16.1.5 | Proxmox host (GPU) |

### Talos K8s Nodes

| Name | IP | Role | Host |
|------|-----|------|------|
| talos-cp-1 | 172.16.1.50 | controlplane | pve1 |
| talos-cp-2 | 172.16.1.51 | controlplane | pve2 |
| talos-cp-3 | 172.16.1.52 | controlplane | pve1 |
| talos-worker-1 | 172.16.1.53 | worker | pve2 |

### K8s Network

| Resource | IP |
|----------|-----|
| Talos API VIP | 172.16.1.49 |
| k8s-gateway | 172.16.1.60 |
| envoy-internal | 172.16.1.61 |
| envoy-external | 172.16.1.62 |

## Service Inventory

### On Kubernetes (ragas.cc)

| Service | URL | Status |
|---------|-----|--------|
| Homepage | home.ragas.cc | ✅ Deployed |
| Bazarr | bazarr.ragas.cc | ✅ Deployed |
| Grafana | grafana.ragas.cc | ✅ Deployed |
| Prometheus | prometheus.ragas.cc | ✅ Deployed |
| MkDocs | docs.ragas.cc | ✅ Deployed |

### On LXC: arr (172.16.1.31) - Docker

| Service | URL | Port |
|---------|-----|------|
| Sonarr | sonarr.ragas.cc | 8989 |
| Radarr | radarr.ragas.cc | 7878 |
| Prowlarr | prowlarr.ragas.cc | 9696 |
| Overseerr | seerr.ragas.cc | 5055 |
| Requestrr | requestrr.ragas.cc | 4545 |
| Huntarr | huntarr.ragas.cc | 9705 |
| Dockge | dockge.ragas.cc | 5001 |

### On LXC: torrent (172.16.1.32) - Docker

| Service | URL | Port | Notes |
|---------|-----|------|-------|
| qBittorrent | qbit.ragas.cc | 8080 | 2.5Gb NIC - keep on LXC |

### On LXC: fun (172.16.1.7) - Runtipi

| Service | URL | Status |
|---------|-----|--------|
| Homepage | ~~homepage.ragas.cc~~ | ✅ Migrated to K8s |
| Bazarr | ~~bazarr.ragas.cc~~ | ✅ Migrated to K8s |
| Speedtest | speedtest.ragas.cc | 🔄 Pending migration |
| Overseerr | overseerr.ragas.cc | 🔄 Pending migration |
| NextGBA | nextgba.ragas.cc | 🔄 Pending migration |

### On LXC: Media (GPU required - stay on LXC)

| Service | IP | URL | Notes |
|---------|-----|-----|-------|
| Plex | 172.16.1.33 | plex.ragas.sh | GPU passthrough |
| Jellyfin | 172.16.1.30 | jelly.ragas.sh | GPU + USB |

### On LXC: Infrastructure (stay on LXC)

| Service | IP | Notes |
|---------|-----|-------|
| AdGuard | 172.16.1.11 | DNS must be outside K8s |
| bind9 | 172.16.1.10 | Internal DNS for ragas.cc |
| PBS | 172.16.1.12 | Proxmox Backup Server |
| Uptime Kuma | 172.16.1.249 | Status monitoring |
| Unifi | 172.16.1.253 | Network controller |

### NAS (172.16.1.250)

Synology NAS with NFS shares:
- `/volume2/media` - Media files (movies, TV, music)

**NFS Access:** Currently only LXC containers can mount. K8s workers (172.16.1.50-53) need to be added to NAS allowed hosts.

## Decision Rules: K8s vs LXC

| Condition | Deploy To |
|-----------|-----------|
| Needs GPU? | LXC on pve4 |
| Needs 2.5Gb NIC? | LXC (torrent) |
| Is DNS service? | LXC (outside K8s) |
| Needs USB passthrough? | LXC |
| Stateless web app? | K8s |
| Arr stack app? | K8s (preferred) or LXC |
| Public-facing (ragas.sh)? | Keep existing setup |

## Migration Notes

### Domain Changes
- **Old internal domain:** `*.ragas.sh` (some services)
- **New internal domain:** `*.ragas.cc`
- When migrating, update `base_url` configs from `/app.ragas.sh/` to `/`
- Update DNS in bind9 (`/etc/bind/db.ragas.cc` on 172.16.1.10)

### Config Migration Pattern
1. Backup config from source: `tar -czf /tmp/app-config.tar.gz -C /path/to/config .`
2. Copy to K8s pod: `kubectl cp /tmp/app-config.tar.gz namespace/pod:/tmp/`
3. Extract in pod: `kubectl exec pod -- tar -xzf /tmp/app-config.tar.gz -C /config`
4. Fix base_url if needed: `sed -i 's|base_url:.*|base_url: /|' config.yaml`
5. Restart pod to apply

### NFS Media Mount (Pending)
K8s pods cannot mount NAS NFS until NAS is configured to allow worker IPs.
Workaround: Apps can still connect to Sonarr/Radarr via API without direct media access.

## Key Tools

| Tool | Purpose |
|------|---------|
| `talosctl` | Manage Talos nodes (no SSH!) |
| `kubectl` | Kubernetes CLI |
| `flux` | GitOps CLI |
| `task` | Task runner |
| `sops` | Encrypt/decrypt secrets |
| `talhelper` | Generate Talos configs |

## Common Commands

```bash
# Flux reconciliation
flux reconcile ks <app> -n <namespace> --with-source

# Check status
flux get ks -A
flux get hr -A
kubectl get pods -A

# Talos (NO SSH - API only)
talosctl --nodes <ip> health
talosctl --nodes <ip> dashboard

# DNS updates (on 172.16.1.10)
ssh root@172.16.1.10 "vim /etc/bind/db.ragas.cc"
ssh root@172.16.1.10 "systemctl reload bind9"

# SOPS secrets
sops --encrypt --in-place secret.sops.yaml
sops --decrypt secret.sops.yaml
```

## Repositories

| Repo | Path | Purpose |
|------|------|---------|
| k3s-homelab | /root/homelab/k3s | K8s manifests (this repo) |
| iac | /root/homelab/iac | LXC/Proxmox configs |

## References

- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
- [kubesearch.dev](https://kubesearch.dev/) - Search for app configs
