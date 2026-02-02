# Media Stack (Arr Apps)

The cluster runs a complete media automation stack for managing TV shows, movies, and downloads.

## Services

| Service | URL | Purpose | Database |
|---------|-----|---------|----------|
| Sonarr | https://sonarr.ragas.cc | TV show management | PostgreSQL |
| Radarr | https://radarr.ragas.cc | Movie management | PostgreSQL |
| Prowlarr | https://prowlarr.ragas.cc | Indexer management | PostgreSQL |
| Overseerr | https://request.ragas.sh | Media requests (public) | SQLite |
| Seerr | https://seerr.ragas.cc | Media requests (internal) | PostgreSQL |
| Huntarr | https://huntarr.ragas.cc | Missing media hunter | - |
| Agregarr | https://agg.ragas.cc | Plex collections manager | - |
| Unpackerr | (internal) | Archive extraction | - |
| Requestrr | https://requestrr.ragas.cc | Discord bot for requests | - |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Requests                                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Overseerr  │    │    Seerr    │    │  Requestrr  │         │
│  │  (public)   │    │  (internal) │    │  (Discord)  │         │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘         │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Media Management                           │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   Sonarr    │    │   Radarr    │    │  Prowlarr   │         │
│  │  (TV Shows) │    │  (Movies)   │    │ (Indexers)  │         │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘         │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │ qBittorrent │    │  Unpackerr  │    │   Huntarr   │         │
│  │   (LXC)     │    │  (Extract)  │    │  (Missing)  │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Media Storage                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              NFS (NAS 172.16.1.250)                     │   │
│  │              /volume2/media (10TB+)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Media Servers                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │    Plex     │    │  Jellyfin   │    │   Agregarr  │         │
│  │   (LXC)     │    │   (LXC)     │    │(Collections)│         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

## Storage

All arr apps use **CephFS** for config storage (RWX, instant failover).

| App | PVC | Size |
|-----|-----|------|
| Sonarr | sonarr-config | 10Gi |
| Radarr | radarr-config | 10Gi |
| Prowlarr | prowlarr-config | 5Gi |
| Seerr | seerr-config | 5Gi |
| Overseerr | overseerr-config | 5Gi |
| Huntarr | huntarr-config | 2Gi |
| Unpackerr | unpackerr-config | 1Gi |
| Requestrr | requestrr-config | 1Gi |

Media files are on **NFS** (NAS-backed, 10TB+).

## Database

Arr apps use shared **PostgreSQL** (`postgres.database.svc`):

```bash
# Check database connections
kubectl exec -it postgres-0 -n database -- psql -U tipi -c "\l"
```

Databases: `sonarr_main`, `sonarr_log`, `radarr_main`, `radarr_log`, `prowlarr_main`, `prowlarr_log`, `seerr`

## Image Updates

All images are tracked by **Flux Image Automation**:

```bash
# Check latest available versions
kubectl get imagepolicy -n flux-system

# Force scan for new images
flux reconcile image repository sonarr -n flux-system
```

## Common Tasks

### Restart an app

```bash
kubectl rollout restart deploy sonarr -n default
```

### Check logs

```bash
kubectl logs -f deploy/sonarr -n default
```

### Access app shell

```bash
kubectl exec -it deploy/sonarr -n default -- /bin/bash
```

### Backup configs

Configs are on CephFS (replicated). For manual backup:

```bash
kubectl cp default/sonarr-xxx:/config ./sonarr-backup
```

## Troubleshooting

### App not connecting to PostgreSQL

```bash
# Check PostgreSQL pod
kubectl get pods -n database

# Test connection from app
kubectl exec -it deploy/sonarr -n default -- \
  psql -h postgres.database.svc -U tipi -d sonarr_main -c "SELECT 1"
```

### Media not visible

1. Check NFS mount:
   ```bash
   kubectl exec -it deploy/sonarr -n default -- ls -la /media
   ```

2. Check permissions (should be UID 1000):
   ```bash
   kubectl exec -it deploy/sonarr -n default -- id
   ```

### Indexer issues (Prowlarr)

```bash
# Check Prowlarr logs
kubectl logs -f deploy/prowlarr -n default

# Verify sync to Sonarr/Radarr
# Go to Prowlarr UI -> Settings -> Apps
```
