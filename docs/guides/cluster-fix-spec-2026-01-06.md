# Cluster Fix Spec (Approved)

**Date:** 2026-01-06

## Goals

1. Fix Flux reconciliation failures caused by unused NFS PV/PVC manifests.
2. Ensure all app `*-config` PVCs are GitOps-managed (CephFS).
3. Improve observability:
   - Enable Cilium Hubble + expose UI at `https://hubble.ragas.cc`
   - Add central cluster logging (Loki + Promtail) and wire into Grafana

> Note on “sticky” behavior: the Flux prune-protection annotation for PVCs only prevents **deletion** via GitOps; it does **not** slow down rescheduling after a node failure. Slow recovery on node death is usually caused by node readiness/eviction timing or RBD `VolumeAttachment` cleanup, not by CephFS (RWX) PVCs.

## Implementation Plan

### Phase 1 — Remove broken NFS config PV/PVC resources

- Stop applying the legacy `*-config-nfs` PV/PVC manifests.
- Let Flux prune the unused NFS objects (PVCs/PVs).

### Phase 2 — GitOps-manage CephFS config PVCs

- Add `pvc.yaml` for each application config claim (RWX + `ceph-filesystem`).
- Add `kustomize.toolkit.fluxcd.io/prune: disabled` to PVC metadata.

### Phase 3 — Cleanup abandoned PVs

- Identify `Released` PVs that are no longer referenced.
- Manually `kubectl delete pv ...` once confirmed safe.

### Phase 4 — Cilium HA + Hubble

- Set `operator.replicas: 2`.
- Enable Hubble, Hubble Relay, and Hubble UI.
- Add a Gateway API `HTTPRoute` for `hubble.ragas.cc` via `envoy-internal`.

### Phase 5 — Central logging (Loki + Promtail)

- Deploy Loki (SingleBinary) with filesystem storage on `ceph-block`.
- Deploy Promtail as a DaemonSet and push logs to Loki.
- Add a Grafana datasource (ConfigMap picked up by Grafana sidecar).

### Phase 6 — Validation

- Run repo validators (Taskfile): `task test`.
- Confirm:
  - `flux get ks -A` shows all Ready
  - `hubble.ragas.cc` is reachable
  - Grafana has Loki datasource and logs are queryable
