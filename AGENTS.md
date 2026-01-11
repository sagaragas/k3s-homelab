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
| talos-cp-2 | 172.16.1.51 | controlplane | pve2 | 501 |
| talos-cp-3 | 172.16.1.52 | controlplane | pve4 | 502 |
| talos-worker-1 | 172.16.1.53 | worker | pve1 | 510 |
| talos-worker-2 | 172.16.1.54 | worker | pve2 | 511 |
| talos-worker-3 | 172.16.1.55 | worker | pve3 | 512 |
| talos-worker-4 | 172.16.1.56 | worker | pve4 | 513 |

> **HA Distribution:** Each PVE host has max 1 control plane. Any single host failure maintains etcd quorum (2/3 CPs).

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

### On LXC: torrent (172.16.1.32) - Docker

| Service | URL | Port | Notes |
|---------|-----|------|-------|
| qBittorrent | qbit.ragas.cc | 8080 | 2.5Gb NIC - keep on LXC |

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

**NFS Access:** K8s workers (172.16.1.53-56) and LXC containers can mount NFS shares.

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

## Storage Strategy

| Storage Type | Use Case | Notes |
|--------------|----------|-------|
| **CephFS (ceph-filesystem)** | All application configs | Kernel mounter, RWX, instant failover |
| **Ceph RBD (ceph-block)** | Databases only | PostgreSQL, Prometheus, Grafana |
| **NFS (NAS)** | Media files, backups | Read-heavy, 172.16.1.250 |

**IMPORTANT:**
- CephFS uses kernel mounter (not FUSE) - 5x faster metadata ops
- Talos 1.11+ has IMA disabled, kernel CephFS works properly
- Never use NFS for SQLite - causes corruption

### Current PVCs

| App | Storage Class | Size |
|-----|---------------|------|
| Sonarr | ceph-filesystem | 10Gi |
| Radarr | ceph-filesystem | 10Gi |
| Prowlarr | ceph-filesystem | 5Gi |
| Seerr | ceph-filesystem | 5Gi |
| Bazarr | ceph-filesystem | 5Gi |
| Huntarr | ceph-filesystem | 2Gi |
| Requestrr | ceph-filesystem | 1Gi |
| Unpackerr | ceph-filesystem | 1Gi |
| Speedtest | ceph-filesystem | 1Gi |
| PostgreSQL | ceph-block | 10Gi |
| Prometheus | ceph-block | 50Gi |
| Grafana | ceph-block | 10Gi |
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
| `talhelper` | Generate/apply/upgrade Talos configs (`task talos:*`) |

## Adding New Talos Nodes

Preferred: add the node to `talos/talconfig.yaml`, then generate/apply configs via Taskfile (generated machine configs land in `talos/clusterconfig/` and are gitignored).

```bash
task talos:generate-config
task talos:apply-node IP=<new-node-ip> MODE=auto
```

Fallback (quick/manual): copy the machine config from an existing worker node, edit it, and apply in maintenance mode.

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
