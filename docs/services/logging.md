# Logging (Loki + Promtail)

The cluster uses Loki for log storage and Promtail to ship logs from nodes/pods into Loki.

## Components

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Loki | `monitoring` | Log storage + query API |
| Promtail | `monitoring` | Log shipping to Loki |

## Grafana integration

Grafana is configured with a Loki datasource via a ConfigMap.

## Troubleshooting

```bash
# Loki / Promtail pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Recent logs
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=200
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=200
```

## Files

- Loki HelmRelease: `kubernetes/apps/monitoring/loki/app/helmrelease.yaml`
- Promtail HelmRelease: `kubernetes/apps/monitoring/promtail/app/helmrelease.yaml`
- Grafana datasource: `kubernetes/apps/monitoring/kube-prometheus-stack/app/loki-datasource.yaml`
