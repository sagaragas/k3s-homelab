# DNS & Ingress

This document covers the networking stack: Envoy Gateway, k8s-gateway, and Cilium LoadBalancer.

## Overview

| Component | Purpose | IP/Port |
|-----------|---------|---------|
| Envoy Gateway | HTTP/HTTPS ingress | 172.16.1.61 (internal) |
| k8s-gateway | Split-horizon DNS | 172.16.1.60:53 |
| Cilium | LoadBalancer + CNI | L2 announcements |

## Traffic Flow

```
┌──────────┐    DNS     ┌─────────────┐
│  Client  │───────────▶│  AdGuard    │
└──────────┘            │  (rewrite)  │
     │                  └──────┬──────┘
     │                         │
     │ *.ragas.cc             ▼
     │                  ┌─────────────┐
     │                  │ k8s-gateway │ (optional)
     │                  │ 172.16.1.60 │
     │                  └──────┬──────┘
     │                         │ 172.16.1.61
     ▼                         ▼
┌─────────────────────────────────────┐
│         Envoy Gateway               │
│         172.16.1.61                 │
└──────────────────┬──────────────────┘
                   │ HTTPRoute
                   ▼
            ┌──────────────┐
            │   Service    │
            └──────────────┘
```

## Envoy Gateway

### Gateways

Two gateways are configured:

| Gateway | IP | Purpose |
|---------|-----|---------|
| envoy-internal | 172.16.1.61 | Local network access |
| envoy-external | 172.16.1.62 | External/Cloudflare (disabled) |

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

TLS is handled by a wildcard certificate:

- **Secret**: `ragas-cc-production-tls` in `network` namespace
- **Covers**: `*.ragas.cc` and `ragas.cc`
- **Issuer**: Let's Encrypt via cert-manager

## k8s-gateway (Split DNS)

k8s-gateway provides DNS responses for cluster services, enabling split-horizon DNS.

### How It Works

1. AdGuard/router forwards `*.ragas.cc` queries to k8s-gateway (172.16.1.60)
2. k8s-gateway looks up HTTPRoutes and returns the gateway IP
3. Client connects to the gateway IP

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

Add DNS rewrite:
```
*.ragas.cc → 172.16.1.61
```

Or use conditional forwarding:
```
[/ragas.cc/]172.16.1.60
```

### Technitium DNS

Create zone `ragas.cc` with:
```
*.ragas.cc  A  172.16.1.61
```

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
