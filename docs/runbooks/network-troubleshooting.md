# Runbook: Network Troubleshooting

## Symptoms

- Pods can't communicate
- Services unreachable
- DNS resolution failing
- External access not working

## Quick Checks

```bash
# Check Cilium status
cilium status

# Check pod networking
kubectl get pods -A -o wide

# Check services
kubectl get svc -A

# Check gateways
kubectl get gateway -A
kubectl get httproute -A
```

## Diagnosis Tools

### Debug Pod

```bash
# Deploy debug pod
kubectl run debug --rm -it --image=alpine -- sh

# Inside pod:
apk add curl bind-tools
nslookup kubernetes
curl http://service.namespace.svc.cluster.local
```

### Cilium Connectivity Test

```bash
cilium connectivity test
```

## Common Issues

### 1. DNS Not Resolving

```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test DNS
kubectl run -it --rm debug --image=alpine -- nslookup kubernetes.default
```

**Fix**: Restart CoreDNS
```bash
kubectl rollout restart deployment coredns -n kube-system
```

### 2. Pod-to-Pod Communication Failing

```bash
# Check Cilium agents
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=50

# Check network policies
kubectl get cnp,ccnp -A
```

**Fix**: Restart Cilium
```bash
kubectl rollout restart daemonset cilium -n kube-system
```

### 3. Service Not Reachable

```bash
# Check service endpoints
kubectl get endpoints <service-name>

# Check if pods match selector
kubectl get pods -l <selector>

# Check service port configuration
kubectl describe svc <service-name>
```

**Fix**: Verify selector matches pod labels

### 4. LoadBalancer IP Not Assigned

```bash
# Check Cilium L2 announcements
kubectl get ciliumbgppeeringpolicy
kubectl get ciliumloadbalancerippool

# Check service
kubectl describe svc <service-name>
```

**Fix**: Verify IP pool has available addresses

### 5. HTTPRoute Not Working

```bash
# Check gateway status
kubectl describe gateway envoy-internal -n network

# Check HTTPRoute status
kubectl describe httproute <name> -n <namespace>

# Check Envoy pods
kubectl get pods -n network -l app.kubernetes.io/name=envoy
kubectl logs -n network -l app.kubernetes.io/name=envoy
```

**Fix**: Verify gateway is listening and route is attached

### 6. External DNS Not Updating

```bash
# Check external-dns logs
kubectl logs -n network -l app.kubernetes.io/name=external-dns

# Verify Cloudflare API token
kubectl get secret -n network cloudflare-api-token
```

**Fix**: Check API token permissions and DNS zone settings

## Network Policy Debugging

```bash
# List all policies
kubectl get ciliumnetworkpolicy -A
kubectl get networkpolicy -A

# Check if traffic is being dropped
cilium monitor --type drop

# Test with policy temporarily removed
kubectl delete cnp <policy-name> -n <namespace>
```

## MTU Issues

```bash
# Check MTU settings
kubectl get configmap -n kube-system cilium-config -o yaml | grep mtu

# If packets are being dropped due to MTU
# Update Cilium config with correct MTU
```

## Useful Commands

```bash
# Watch real-time network events
cilium monitor

# Check BPF maps
cilium bpf endpoint list
cilium bpf lb list

# Trace packet flow
cilium monitor --type trace
```

## Prevention

- Test connectivity after changes
- Use network policies incrementally
- Monitor Cilium metrics in Prometheus
- Keep Cilium updated
