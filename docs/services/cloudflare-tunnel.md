# Cloudflare Tunnel

Cloudflare Tunnel provides inbound access to selected public hostnames without exposing the cluster directly to the internet.

## Architecture

```
Client → Cloudflare → Tunnel (cloudflared) → Envoy Gateway (envoy-external) / specific services
```

- Runs in the `network` namespace.
- Deployed as two replicas for availability.

## Configuration

- HelmRelease: `kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml`
- Credentials: `kubernetes/apps/network/cloudflare-tunnel/app/secret.sops.yaml` (Secret: `cloudflare-tunnel-secret`)
- Ingress rules are defined in the embedded `config.yaml` in the HelmRelease values.

## Observability

`cloudflared` exposes a readiness endpoint on port `8080` and is scraped via a ServiceMonitor (see the HelmRelease).

## Troubleshooting

```bash
# Pods / logs
kubectl get pods -n network -l app.kubernetes.io/name=cloudflare-tunnel
kubectl logs -n network -l app.kubernetes.io/name=cloudflare-tunnel --tail=200

# Readiness check
kubectl port-forward -n network deploy/cloudflare-tunnel 8080:8080
curl -fsS http://127.0.0.1:8080/ready
```
