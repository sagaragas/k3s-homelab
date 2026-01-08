# DNS & Ingress

This document covers the networking stack: Envoy Gateway, k8s-gateway, and Cilium LoadBalancer.

## Overview

| Component | Purpose | IP/Port |
|-----------|---------|---------|
| Envoy Gateway (internal) | HTTP/HTTPS ingress for `*.ragas.cc` | 172.16.1.61 |
| Envoy Gateway (external) | Gateway behind Cloudflare tunnel for `*.ragas.sh` | 172.16.1.62 |
| Cloudflare Tunnel | Public ingress (Cloudflare → cluster) | in-cluster |
| k8s-gateway | Split-horizon DNS for `ragas.cc` (HTTPRoutes/Services) | 172.16.1.60:53 |
| Cilium | LoadBalancer + CNI | L2 announcements |

## Traffic Flow

### Internal (`ragas.cc`)

```
Client → AdGuard → (optional) k8s-gateway (172.16.1.60) → envoy-internal (172.16.1.61) → Service
```

### External (`ragas.sh`)

```
Internet → Cloudflare → Cloudflare Tunnel → envoy-external → Service
```

## Envoy Gateway

### Gateways

Two gateways are configured:

| Gateway | IP | Purpose |
|---------|-----|---------|
| envoy-internal | 172.16.1.61 | Local network access |
| envoy-external | 172.16.1.62 | Public services via Cloudflare tunnel (`ragas.sh`) |

### Creating an HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp
  namespace: default
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "myapp.ragas.cc"
  rules:
    - backendRefs:
        - name: myapp
          port: 80
```

### TLS Configuration

TLS is handled by cert-manager Certificates:

- `ragas-cc-production-tls` (network): `ragas.cc` + `*.ragas.cc`
- `ragas-sh-production-tls` (network): `ragas.sh` + `*.ragas.sh`

## k8s-gateway (Split DNS)

k8s-gateway provides DNS responses for cluster services, enabling split-horizon DNS.

### How It Works

1. (Optional) AdGuard/router forwards `ragas.cc` queries to k8s-gateway (172.16.1.60)
2. k8s-gateway watches `HTTPRoute` and `Service` resources and returns the appropriate LoadBalancer IP
3. Client connects to the returned IP (typically `envoy-internal`)

### Configuration

```yaml
domain: ragas.cc
fallthrough: true
secondaryDNS:
  enabled: false
```

### Testing

```bash
# Query k8s-gateway directly
dig @172.16.1.60 home.ragas.cc
dig @172.16.1.60 grafana.ragas.cc

# Should return 172.16.1.61
```

## Cilium LoadBalancer

Cilium provides LoadBalancer services via L2 announcements (ARP).

### IP Pool

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: pool
spec:
  blocks:
    - cidr: "172.16.1.0/24"
```

### L2 Announcement Policy

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
spec:
  loadBalancerIPs: true
  interfaces:
    - ^ens.*
```

### Checking LoadBalancer IPs

```bash
# View assigned IPs
kubectl get svc -A -o wide | grep LoadBalancer

# Check Cilium service list
kubectl exec -n kube-system ds/cilium -- cilium service list
```

## DNS Configuration

### AdGuard Home

Recommended (dynamic): conditional forwarding to k8s-gateway:

```
[/ragas.cc/]172.16.1.60
```

Alternative (static): wildcard `*.ragas.cc` → `172.16.1.61` in your LAN DNS server.

## Troubleshooting

### Service Not Accessible

1. Check HTTPRoute exists:
   ```bash
   kubectl get httproutes -A
   ```

2. Check gateway is programmed:
   ```bash
   kubectl get gateway -n network
   ```

3. Test DNS resolution:
   ```bash
   dig @172.16.1.60 myapp.ragas.cc
   ```

4. Test direct access:
   ```bash
   curl -sk https://172.16.1.61 -H "Host: myapp.ragas.cc"
   ```

### LoadBalancer IP Not Reachable

1. Check L2 announcement policy has correct interface
2. Verify Cilium is healthy: `cilium status`
3. Check ARP table on client machine
4. Note: Ping won't work (only service ports are handled)
