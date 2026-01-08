# Homepage Dashboard

Homepage is a modern, self-hosted dashboard for your homelab services.

## Overview

| Property | Value |
|----------|-------|
| URL | https://home.ragas.cc |
| Namespace | default |
| Chart | jameswynn/homepage |
| Source | [GitHub](https://github.com/gethomepage/homepage) |

## Features

- **Service Widgets**: Real-time status from various services
- **Kubernetes Integration**: Shows cluster status, pods, nodes
- **Bookmarks**: Quick access to frequently used services
- **Customizable**: Themes, layouts, icons

## Configuration

The Homepage configuration is managed via the HelmRelease values:

```yaml
config:
  bookmarks:
    - Developer:
        - Github:
            href: https://github.com/sagaragas
  
  services:
    - Kubernetes:
        - Grafana:
            icon: grafana
            href: https://grafana.ragas.cc
  
  widgets:
    - kubernetes:
        cluster:
          show: true
          cpu: true
          memory: true
  
  settings:
    title: Ragas Homelab
    theme: dark
```

## Adding Services

To add a new service to the dashboard, edit the HelmRelease:

```yaml
services:
  - Category Name:
      - Service Name:
          icon: service-icon  # From dashboard-icons
          href: https://service.ragas.cc
          description: Service description
          widget:
            type: servicetype
            url: http://service.namespace.svc.cluster.local
```

## Service Widgets

Homepage supports widgets for many services:

| Service | Widget Type |
|---------|-------------|
| Grafana | grafana |
| Proxmox | proxmox |
| AdGuard | adguard |
| Portainer | portainer |

### Widget Example

```yaml
- Monitoring:
    - Grafana:
        icon: grafana
        href: https://grafana.ragas.cc
        widget:
          type: grafana
          url: http://grafana.monitoring.svc.cluster.local
```

## Kubernetes Widget

The Kubernetes widget shows cluster status:

```yaml
widgets:
  - kubernetes:
      cluster:
        show: true
        cpu: true
        memory: true
        showLabel: true
        label: "Talos Cluster"
      nodes:
        show: true
        cpu: true
        memory: true
```

## Icons

Homepage uses [Dashboard Icons](https://github.com/walkxcode/dashboard-icons).

Find icons at: https://github.com/walkxcode/dashboard-icons/tree/main/png

Use the filename (without .png) as the icon name:
- `icon: plex`
- `icon: grafana`
- `icon: proxmox`

## Customization

### Themes
```yaml
settings:
  theme: dark  # or light
  color: slate  # slate, gray, zinc, neutral, stone, red, orange, amber, yellow, lime, green, emerald, teal, cyan, sky, blue, indigo, violet, purple, fuchsia, pink, rose
```

### Layout
```yaml
settings:
  layout:
    Category Name:
      style: row  # or column
      columns: 3
```

## Troubleshooting

### Dashboard not loading
```bash
kubectl logs -n default -l app.kubernetes.io/name=homepage
```

### Service not showing status
1. Check service URL is accessible from the pod
2. Verify API keys/tokens are correct
3. Check widget type matches the service

### RBAC Issues
Homepage needs cluster-wide read access for Kubernetes widgets:
```bash
kubectl get clusterrole homepage
kubectl get clusterrolebinding homepage
```

## Files

- HelmRelease: `kubernetes/apps/default/homepage/app/helmrelease.yaml`
- HTTPRoute: `kubernetes/apps/default/homepage/app/httproute.yaml`
- Kustomization: `kubernetes/apps/default/homepage/ks.yaml`
