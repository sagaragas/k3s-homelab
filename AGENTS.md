# k3s-homelab

## Cluster Overview
- **Type:** k3s HA cluster (4 nodes: 2 server, 2 agent)
- **API VIP:** 172.16.1.49 (kube-vip)
- **Nodes:**
  - k3s-cp-1: 172.16.1.50 (server, pve1)
  - k3s-cp-2: 172.16.1.51 (server, pve2)
  - k3s-worker-1: 172.16.1.52 (agent, pve1)
  - k3s-worker-2: 172.16.1.53 (agent, pve2)
- **Domain:** ragas.cc (Cloudflare DNS via external-dns)
- **Storage:** Ceph CSI (StorageClass: ceph-rbd)
- **GitOps:** Flux v2 - push to main triggers deployment
- **Secrets:** SOPS encrypted with age

## Directory Structure
```
kubernetes/
├── flux-system/          # Flux components (auto-generated)
├── infrastructure/       # Cluster services
│   ├── controllers/
│   │   ├── traefik/      # Ingress controller
│   │   ├── cert-manager/ # TLS certificates
│   │   └── external-dns/ # DNS automation
│   └── storage/
│       └── ceph-csi/     # Ceph storage driver
├── apps/                 # Application deployments
└── config/               # Cluster-wide configs and secrets
```

## Adding a New Application
1. Create directory: `kubernetes/apps/<category>/<app-name>/`
2. Add files:
   - `namespace.yaml` (if new namespace)
   - `helmrelease.yaml` or `deployment.yaml`
   - `kustomization.yaml`
   - `secret.sops.yaml` (if secrets needed, encrypt with SOPS)
3. Register in parent kustomization
4. Push to main - Flux deploys automatically

## Ingress Pattern
All apps get automatic DNS + TLS:
```yaml
ingress:
  main:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - host: myapp.ragas.cc
        paths:
          - path: /
    tls:
      - hosts:
          - myapp.ragas.cc
        secretName: myapp-tls
```
Result: external-dns creates DNS record, cert-manager issues TLS cert.

## Secrets Management
```bash
# Create a secret file
cat > secret.sops.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
stringData:
  key: value
EOF

# Encrypt it
sops --encrypt --in-place secret.sops.yaml

# Decrypt for viewing (don't commit decrypted!)
sops --decrypt secret.sops.yaml
```

## Common Commands
| Task | Command |
|------|---------|
| Force Flux sync | `flux reconcile kustomization apps --with-source` |
| Check Flux status | `flux get all -A` |
| View pod logs | `kubectl logs -n <ns> deploy/<name>` |
| Enter pod shell | `kubectl exec -it -n <ns> deploy/<name> -- sh` |
| Check storage | `kubectl get pvc -A` |
| Check certs | `kubectl get certificates -A` |

## Network Layout
| Service | URL |
|---------|-----|
| Traefik Dashboard | traefik.ragas.cc |
| (apps added here as deployed) |

## Related Repository
LXC containers (plex, jellyfin, qbit, etc.) managed in `/root/homelab/iac`

## Control Node
All management runs from ansible LXC (172.16.1.9).
kubeconfig stored at: `~/.kube/config`
