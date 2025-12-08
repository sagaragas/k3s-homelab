# Security Architecture

## Overview

Security is implemented at multiple layers: infrastructure, cluster, and application.

## Infrastructure Security

### Talos Linux

- **No SSH**: All management via API
- **Immutable OS**: Read-only root filesystem
- **Minimal attack surface**: No package manager, no shell
- **mTLS**: All API communication encrypted

### Network Isolation

- VLANs separate management and workload traffic
- Firewall rules on router
- Network policies in Kubernetes

## Cluster Security

### RBAC

Role-Based Access Control limits what users and services can do:

```yaml
# Example: Read-only access to pods
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

### Pod Security

Pod Security Standards enforce security contexts:

```yaml
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
```

### Network Policies

Cilium network policies control pod traffic:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-all
spec:
  endpointSelector: {}
  ingress:
    - {}
  egress:
    - {}
```

## Secrets Management

### SOPS + Age

All secrets are encrypted with SOPS using Age keys:

```bash
# Encrypt a secret
sops --encrypt --in-place secret.yaml

# Decrypt for viewing
sops secret.yaml
```

### Structure

```yaml
# secret.sops.yaml (encrypted)
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
stringData:
  password: ENC[AES256_GCM,data:...,type:str]
sops:
  age:
    - recipient: age1...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
```

### Key Management

- Age private key stored in `age.key` (gitignored)
- Public key in `.sops.yaml` for encryption
- Flux decrypts secrets at deploy time

## TLS/Certificates

### cert-manager

Automatic certificate provisioning:

1. HTTPRoute created
2. cert-manager watches for annotations
3. ACME challenge via Cloudflare DNS-01
4. Certificate stored as Secret
5. Gateway uses certificate

### Certificate Rotation

Certificates auto-renew 30 days before expiry.

## Access Control

### Kubernetes API

- mTLS authentication
- RBAC authorization
- Audit logging (optional)

### Application Access

- Gateway API routes traffic
- TLS termination at gateway
- No direct pod access

## Security Checklist

- [ ] All secrets encrypted with SOPS
- [ ] Network policies for each namespace
- [ ] Pod security contexts configured
- [ ] RBAC roles minimized
- [ ] Certificates auto-renewing
- [ ] No `latest` tags in images
- [ ] Image pull from trusted registries
- [ ] Regular Talos/K8s updates

## Incident Response

### Suspected Compromise

1. **Isolate**: Apply deny-all network policy
2. **Investigate**: Check logs, audit trail
3. **Contain**: Delete compromised resources
4. **Recover**: Redeploy from Git
5. **Review**: Update security policies

### Key Rotation

```bash
# Generate new Age key
age-keygen -o new-age.key

# Re-encrypt all secrets with new key
# Update Flux with new key
```
