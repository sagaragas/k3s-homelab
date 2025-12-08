# Monitoring Stack

The cluster uses kube-prometheus-stack for comprehensive monitoring.

## Components

| Component | URL | Purpose |
|-----------|-----|---------|
| Prometheus | https://prometheus.ragas.cc | Metrics collection & storage |
| Grafana | https://grafana.ragas.cc | Visualization & dashboards |
| Alertmanager | https://alertmanager.ragas.cc | Alert routing & notification |

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Grafana | admin | admin (change immediately!) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Monitoring Stack                         │
│                                                                  │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │  Prometheus  │──▶│   Grafana    │   │ Alertmanager │        │
│  │   Metrics    │   │  Dashboards  │   │   Alerts     │        │
│  └──────────────┘   └──────────────┘   └──────────────┘        │
│         ▲                                      │                │
│         │                                      ▼                │
│  ┌──────┴───────────────────────────────────────────────────┐  │
│  │                    ServiceMonitors                        │  │
│  │                                                           │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐     │  │
│  │  │ Cilium  │  │ CoreDNS │  │  etcd   │  │ Kubelet │     │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘     │  │
│  │                                                           │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐     │  │
│  │  │  Node   │  │ API     │  │Controller│  │ Custom  │     │  │
│  │  │Exporter │  │ Server  │  │ Manager │  │  Apps   │     │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Pre-built Dashboards

kube-prometheus-stack includes these dashboards:

- **Kubernetes / Compute Resources / Cluster**
- **Kubernetes / Compute Resources / Namespace (Pods)**
- **Kubernetes / Compute Resources / Node (Pods)**
- **Kubernetes / Networking / Cluster**
- **Node Exporter / Nodes**
- **CoreDNS**
- **etcd**

## Adding Custom Dashboards

### Method 1: ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    {
      "title": "My Dashboard",
      ...
    }
```

### Method 2: Grafana UI

1. Login to Grafana
2. Create dashboard
3. Save dashboard
4. Export JSON and add to ConfigMap for persistence

## Adding ServiceMonitors

To monitor a new service, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: my-app
  namespaceSelector:
    matchNames:
      - default
  endpoints:
    - port: metrics
      interval: 30s
```

## Alerting

### View Alerts

```bash
# Current alerts in Prometheus
curl -s http://prometheus.ragas.cc/api/v1/alerts | jq

# Alertmanager status
curl -s http://alertmanager.ragas.cc/api/v2/alerts | jq
```

### Custom AlertRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: my-app
      rules:
        - alert: MyAppDown
          expr: up{job="my-app"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "MyApp is down"
            description: "MyApp has been down for 5 minutes"
```

## Storage

| Component | Storage | Size |
|-----------|---------|------|
| Prometheus | PVC | 20Gi |
| Alertmanager | PVC | 1Gi |
| Grafana | PVC | 5Gi |

## Retention

Default retention settings:
- **Time**: 7 days
- **Size**: 10GB

Adjust in HelmRelease:
```yaml
prometheus:
  prometheusSpec:
    retention: 14d
    retentionSize: 20GB
```

## Troubleshooting

### Prometheus not scraping
```bash
# Check targets
curl http://prometheus.ragas.cc/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Check ServiceMonitor
kubectl get servicemonitor -A
kubectl describe servicemonitor <name> -n monitoring
```

### Grafana datasource issues
```bash
# Check datasource config
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.datasources\.yaml}' | base64 -d
```

### High memory usage
```bash
# Check Prometheus memory
kubectl top pod -n monitoring -l app.kubernetes.io/name=prometheus

# Check cardinality
curl http://prometheus.ragas.cc/api/v1/status/tsdb | jq
```

## Files

- HelmRelease: `kubernetes/apps/monitoring/kube-prometheus-stack/app/helmrelease.yaml`
- HTTPRoutes: `kubernetes/apps/monitoring/kube-prometheus-stack/app/httproutes.yaml`
- Kustomization: `kubernetes/apps/monitoring/kube-prometheus-stack/ks.yaml`
