# Homelab Progress Report - 2026-01-04

## Session Summary

This session focused on migrating services from LXC to Kubernetes, scaling the cluster, and improving the Homepage dashboard.

---

## Completed Work

### 1. Cluster Scaling
- **Added 3 new worker nodes** to the Talos K8s cluster:
  - talos-worker-2 (172.16.1.54) on pve4
  - talos-worker-3 (172.16.1.55) on pve4
  - talos-worker-4 (172.16.1.56) on pve3
- **Fixed terraform drift** - Recreated workers with correct storage (vm-storage/ceph, 200GB/100GB disks)
- **All 7 nodes healthy**: 3 control planes + 4 workers

### 2. Service Migrations (LXC → K8s)

| Service | Old Location | New Location | Status |
|---------|--------------|--------------|--------|
| Speedtest Tracker | fun LXC (172.16.1.7) | K8s (speed.ragas.cc) | ✅ Complete |
| PostgreSQL | fun LXC | K8s (postgres.database.svc) | ✅ Complete |
| Seerr | arr LXC (172.16.1.31) | K8s (request.ragas.sh) | ✅ Complete |
| Sonarr | arr LXC (172.16.1.31) | K8s (sonarr.ragas.cc) | ✅ Complete |
| Radarr | arr LXC (172.16.1.31) | K8s (radarr.ragas.cc) | ✅ Complete |

**Migration details:**
- All configs backed up and restored with zero data loss
- Sonarr/Radarr use shared NFS PV for media access (172.16.1.250:/volume2/hulk/media)
- Seerr routes through Cloudflare tunnel for public access (ragas.sh)
- Old containers removed from arr LXC

### 3. Storage Setup
- **Ceph RBD** for app configs (replicated, safe on reboot)
- **NFS PV** (media-nfs, 10Ti) for shared media access from NAS
- NFS allowed from K8s worker IPs (172.16.1.50-56)

### 4. Homepage Dashboard Updates
- **Theme**: Applied Glass Morphism style
  - Frosted glass cards with backdrop-filter blur
  - Inter font family
  - Mountain landscape background
  - Slate color scheme
- **Services updated** to point to K8s:
  - Seerr → http://seerr.default.svc.cluster.local:5055
  - Sonarr → http://sonarr.default.svc.cluster.local:8989
  - Radarr → http://radarr.default.svc.cluster.local:7878
- **Kubernetes widget**: Shows cluster + 7 nodes CPU/memory in top bar
- **Replaced Cloudflare widget** with Speedtest Tracker (no API token needed)
- **Fixed Seerr API key**: MTc2NTc4MTkyOTc2Mjk5OTM5M2JiLWNlM2QtNGMxNy04N2NjLTE1MGIxNTk2MmU1Ng==
- **Layout**: Network section 3 columns, Requests 1 column

### 5. Bug Fixes
- **ct9999 on pve2**: Removed stuck create lock, deleted incomplete container
- **Kubernetes widget 500 error**: Added `mode: cluster` to kubernetes config
- **Homepage icons**: Fixed speedtest-tracker icon (si-speedtest)
- **DNS caching**: Flushed Chrome net-internals for sonarr.ragas.cc

---

## Current State

### K8s Cluster
```
NAME             STATUS   ROLES           IP
talos-cp-1       Ready    control-plane   172.16.1.50
talos-cp-2       Ready    control-plane   172.16.1.51
talos-cp-3       Ready    control-plane   172.16.1.52
talos-worker-1   Ready    worker          172.16.1.53
talos-worker-2   Ready    worker          172.16.1.54
talos-worker-3   Ready    worker          172.16.1.55
talos-worker-4   Ready    worker          172.16.1.56
```

### Speedtest Tracker
- **Pinned to**: talos-worker-4 (pve3, 172.16.1.56)
- **Schedule**: Daily at 7 AM (`0 7 * * *`)
- **Server**: Jefferson Union High School District (ID: 19900)
- **Latest result**: 416 Mbps down / 300 Mbps up / 12ms ping

### Services on K8s
- Homepage: home.ragas.cc
- Speedtest: speed.ragas.cc
- Sonarr: sonarr.ragas.cc
- Radarr: radarr.ragas.cc
- Seerr: request.ragas.sh (public via CF tunnel)
- Bazarr: bazarr.ragas.cc
- Grafana: grafana.ragas.cc
- Prometheus: prometheus.ragas.cc

### Services Still on LXC
- **arr LXC (172.16.1.31)**: Prowlarr, Requestrr, Huntarr, Dockge
- **torrent LXC (172.16.1.32)**: qBittorrent (2.5Gb NIC - keep here)
- **Plex (172.16.1.33)**: GPU passthrough required
- **Jellyfin (172.16.1.30)**: GPU + USB required
- **Infrastructure**: AdGuard, bind9, PBS, Uptime Kuma, Unifi

---

## Pending Tasks

### High Priority
1. **Test Seerr integration** - Verify it can communicate with K8s Sonarr/Radarr
2. **Update Seerr internal config** - Point to K8s services via web UI or settings.json

### Medium Priority
3. **Migrate remaining arr services** (if desired):
   - Prowlarr (indexer manager)
   - Requestrr (Discord bot)
   - Huntarr (missing media finder)
4. **Cloudflare API token** - Create token for Homepage widget (optional)

### Low Priority
5. **Plan Plex/Jellyfin migration** - Requires GPU passthrough to K8s
6. **Backup strategy** - PVCs have Delete reclaim policy, consider Velero
7. **Homepage theme tweaks** - Adjust if needed after testing

---

## Key Files Modified

### K8s Manifests
- `kubernetes/apps/default/speedtest-tracker/app/helmrelease.yaml` - Pinned to worker-4
- `kubernetes/apps/default/homepage/app/helmrelease.yaml` - Theme, widgets, services
- `kubernetes/apps/default/homepage/app/secret.sops.yaml` - Updated Seerr API key
- `kubernetes/apps/default/seerr/app/helmrelease.yaml` - Seerr deployment
- `kubernetes/apps/default/sonarr/app/helmrelease.yaml` - Sonarr + NFS mount
- `kubernetes/apps/default/radarr/app/helmrelease.yaml` - Radarr + NFS mount
- `kubernetes/apps/default/media-storage/app/pv.yaml` - Shared NFS PV/PVC

### Documentation
- `AGENTS.md` - Updated with migration status

---

## Useful Commands

```bash
# Flux reconcile
flux reconcile ks <app> -n <namespace> --with-source

# Check all pods
kubectl get pods -A | grep -v Running

# Trigger speedtest manually
# Go to https://speed.ragas.cc and click "Run Speedtest"

# Check homepage logs
kubectl logs deployment/homepage -n default --tail=50

# DNS updates (bind9)
ssh root@172.16.1.10 "vim /etc/bind/db.ragas.cc && systemctl reload bind9"
```

---

## Git Commits This Session
```
cadf086 feat(homepage): move kubernetes widget to service card
d4dfcf1 fix(homepage): move kubernetes back to info widget (top bar)
2960d86 fix(homepage): replace cloudflare widget with speedtest tracker
2fb77a8 fix(homepage): use si-speedtest icon for speedtest tracker
4627028 feat(speedtest): pin to talos-worker-4 (pve3)
6d22cb4 fix(homepage): add kubernetes mode=cluster for widget
b6cd1d8 feat(homepage): glass morphism theme + fix seerr API key
```

---

*Last updated: 2026-01-04 ~11:15 UTC*
