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
| **Storage** | Ceph RBD (app data), NFS (backups/media only) |

## Domains

| Domain | Purpose | DNS Provider |
|--------|---------|--------------|
| `ragas.cc` | Internal services (K8s, LXC) | bind9 → AdGuard |
| `ragas.sh` | Public-facing services | Cloudflare |

### Public Services (ragas.sh) - DO NOT MIGRATE DOMAINS
- `request.ragas.sh` → Seerr (public requests, on K8s)
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

| Name | IP | Role | Host | VMID |
|------|-----|------|------|------|
| talos-cp-1 | 172.16.1.50 | controlplane | pve1 | 500 |
| talos-cp-2 | 172.16.1.51 | controlplane | pve1 | 501 |
| talos-cp-3 | 172.16.1.52 | controlplane | pve2 | 502 |
| talos-worker-1 | 172.16.1.53 | worker | pve2 | 510 |
| talos-worker-2 | 172.16.1.54 | worker | pve4 | 511 |
| talos-worker-3 | 172.16.1.55 | worker | pve4 | 512 |
| talos-worker-4 | 172.16.1.56 | worker | pve3 | 513 |

### K8s Network

| Resource | IP |
|----------|-----|
| Talos API VIP | 172.16.1.49 |
| k8s-gateway | 172.16.1.60 |
| envoy-internal | 172.16.1.61 |
| envoy-external | 172.16.1.62 |

## Service Inventory

### On Kubernetes (ragas.cc)

| Service | URL | Status | Notes |
|---------|-----|--------|-------|
| Homepage | home.ragas.cc | ✅ Deployed | 2 replicas |
| Bazarr | bazarr.ragas.cc | ✅ Deployed | |
| Grafana | grafana.ragas.cc | ✅ Deployed | |
| Prometheus | prometheus.ragas.cc | ✅ Deployed | |
| MkDocs | docs.ragas.cc | ✅ Deployed | |
| Speedtest Tracker | speed.ragas.cc | ✅ Deployed | |
| Seerr | request.ragas.sh | ✅ Deployed | 2 replicas, PostgreSQL, public via CF tunnel |
| Sonarr | sonarr.ragas.cc | ✅ Deployed | 2 replicas, PostgreSQL |
| Radarr | radarr.ragas.cc | ✅ Deployed | 2 replicas, PostgreSQL |
| Prowlarr | prowlarr.ragas.cc | ✅ Deployed | 2 replicas, PostgreSQL |
| Requestrr | requestrr.ragas.cc | ✅ Deployed | Discord bot |
| Huntarr | huntarr.ragas.cc | ✅ Deployed | Missing media hunter |
| Unpackerr | (internal) | ✅ Deployed | Archive extraction |
| PostgreSQL | postgres.database.svc | ✅ Deployed | Shared DB for arr apps |

### On LXC: arr (172.16.1.31) - SHUTDOWN

> **Status:** Shutdown on 2026-01-05. Backups at `/volume1/k8s-backup/lxc-backups/arr-lxc-final-20260105.tar.gz`
> **Keep until:** 2026-02-05 (30 days monitoring period)

| Service | Status |
|---------|--------|
| Sonarr | ✅ Migrated to K8s |
| Radarr | ✅ Migrated to K8s |
| Prowlarr | ✅ Migrated to K8s |
| Seerr | ✅ Migrated to K8s |
| Requestrr | ✅ Migrated to K8s |
| Huntarr | ✅ Migrated to K8s |
| Unpackerr | ✅ Migrated to K8s |
| Dockge | ❌ Not migrated (not needed) |

### On LXC: torrent (172.16.1.32) - Docker

| Service | URL | Port | Notes |
|---------|-----|------|-------|
| qBittorrent | qbit.ragas.cc | 8080 | 2.5Gb NIC - keep on LXC |

### On LXC: fun (172.16.1.7) - SHUTDOWN

> **Status:** Shutdown on 2026-01-05. Backups at `/volume1/k8s-backup/lxc-backups/fun-lxc-final-20260105.tar.gz`
> **Keep until:** 2026-02-05 (30 days monitoring period)

| Service | Status |
|---------|--------|
| Homepage | ✅ Migrated to K8s |
| Bazarr | ✅ Migrated to K8s |
| Speedtest | ✅ Migrated to K8s |
| PostgreSQL | ✅ Migrated to K8s |
| Overseerr | ✅ Replaced by Seerr on K8s |
| NextGBA | ❌ Not migrated (low priority) |

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

## Storage Strategy

| Storage Type | Use Case | Notes |
|--------------|----------|-------|
| **Ceph RBD (ceph-block)** | All application data | Distributed, replicated, proper block storage |
| **NFS (NAS)** | Backups, media files | Read-heavy, already on NAS at 172.16.1.250 |

**IMPORTANT:** Never use NFS for SQLite databases - causes corruption due to locking issues.

### Current PVCs

| App | Storage Class | Size |
|-----|---------------|------|
| PostgreSQL | ceph-block | 10Gi |
| Sonarr | ceph-block | 10Gi |
| Radarr | ceph-block | 10Gi |
| Prowlarr | ceph-block | 5Gi |
| Seerr | ceph-block | 5Gi |
| Huntarr | ceph-block | 2Gi |
| Requestrr | ceph-block | 1Gi |
| Unpackerr | ceph-block | 1Gi |
| Bazarr | ceph-block | 5Gi |
| Media (NFS) | - | 10Ti |
| Backups (NFS) | - | 500Gi |

### Resource Policy

- **No CPU/memory limits** - apps scale as needed
- **Generous PVC sizes** - storage is plentiful, don't underprovision
- **Worker node preference** - apps prefer workers but can run on control planes
- **Control planes not tainted** - allows full resource utilization on small clusters

## Key Tools

| Tool | Purpose |
|------|---------|
| `talosctl` | Manage Talos nodes (no SSH!) |
| `kubectl` | Kubernetes CLI |
| `flux` | GitOps CLI |
| `task` | Task runner |
| `sops` | Encrypt/decrypt secrets |
| `talhelper` | Generate Talos configs (NOT USED - see below) |

## Adding New Talos Nodes

**IMPORTANT:** This cluster was NOT created with talhelper. The `talsecret.sops.yaml` was removed because it contained incorrect secrets.

To add a new worker node:

```bash
# 1. Get config template from existing worker
talosctl -n 172.16.1.53 get machineconfig -o jsonpath='{.spec}' > /tmp/new-worker.yaml

# 2. Edit the config - change hostname, IP, MAC address
sed -i 's/talos-worker-1/talos-worker-X/g' /tmp/new-worker.yaml
sed -i 's/172.16.1.53/172.16.1.XX/g' /tmp/new-worker.yaml
sed -i 's/bc:24:11:45:62:22/NEW:MAC:ADDR/g' /tmp/new-worker.yaml

# 3. Boot VM from Talos ISO (maintenance mode)
# 4. Apply config
talosctl apply-config --insecure --nodes <DHCP_IP> --file /tmp/new-worker.yaml

# 5. Verify node joins cluster
kubectl get nodes
```

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
