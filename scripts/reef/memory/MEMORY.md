# Long-Term Memory

Curated knowledge from past operations. Updated by droid after significant events.

## Cluster Patterns

- Ceph occasionally shows HEALTH_WARN for slow ops during heavy media writes — usually self-resolves
- Renovate PRs are almost always safe patch/minor bumps — approve and merge unless critical infra
- CephFS uses kernel mounter (not FUSE) — 5x faster metadata, works on Talos 1.11+
- Never use NFS for SQLite — causes corruption
- Control planes are not tainted — pods can schedule on them

## Past Incidents

### 2026-02-07 — cilium-agent crash-loop on talos-worker-4 (57 restarts)
- **Pod:** `cilium-r49nm` on `talos-worker-4` (172.16.1.56, pve4)
- **Root cause:** Exit code 137 (OOMKilled/SIGKILL) during BPF template compilation at startup. Worker-4 has only 2 CPU / 8GB RAM — the smallest worker — making it most susceptible to memory pressure during cilium's heavy BPF compilation phase.
- **Resolution:** Self-recovered. Pod has been stable since Feb 3 (4+ days). Current memory usage ~150Mi vs 1Gi limit. No action taken.
- **Lesson:** Cilium BPF compilation is memory-intensive on startup. Worker-4's 8GB RAM with many pods can hit OOM during restarts. If this recurs, consider increasing cilium memory limit or reducing pod density on worker-4.

## Operator Preferences

- Sagar prefers full autonomy — fix things, don't ask
- Token usage is not a concern — use Opus 4.6 with max reasoning when needed
- Discord notifications for merges and real problems, not routine health checks
