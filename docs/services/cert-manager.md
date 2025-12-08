# Cert Manager

Cert-manager automates TLS certificate management using Let's Encrypt with Cloudflare DNS-01 challenge.

## Overview

| Component | Value |
|-----------|-------|
| Version | v1.19.1 |
| Namespace | cert-manager |
| Challenge Type | DNS-01 (Cloudflare) |
| Issuer | Let's Encrypt Production |

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│  Certificate    │────▶│ Cert-Manager │────▶│  Cloudflare │
│  Request        │     │  Controller  │     │  DNS API    │
└─────────────────┘     └──────────────┘     └─────────────┘
                               │
                               ▼
                        ┌──────────────┐
                        │ Let's Encrypt│
                        │    ACME      │
                        └──────────────┘
```

## Cluster Issuers

### letsencrypt-production

Used for production certificates with 90-day validity.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: "${SECRET_ACME_EMAIL}"
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cert-manager-secret
              key: api-token
```

### letsencrypt-staging

Used for testing (higher rate limits, not trusted).

## Requesting a Certificate

### Automatic (via Gateway API)

Certificates are automatically requested when you create an HTTPRoute with TLS.

### Manual Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
  namespace: default
spec:
  secretName: my-app-tls-secret
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - myapp.ragas.cc
```

## Cloudflare API Token

The Cloudflare API token requires these permissions:

- **Zone:DNS:Edit** - For creating DNS-01 challenge records
- **Zone:Zone:Read** - For listing zones

Token is stored encrypted in `kubernetes/apps/cert-manager/cert-manager/app/secret.sops.yaml`.

## Troubleshooting

### Check Certificate Status

```bash
# List all certificates
kubectl get certificates -A

# Describe a certificate
kubectl describe certificate <name> -n <namespace>

# Check certificate requests
kubectl get certificaterequests -A

# Check challenges
kubectl get challenges -A
```

### Common Issues

#### Certificate Stuck in "Issuing"

1. Check the CertificateRequest:
   ```bash
   kubectl describe certificaterequest <cert-name>-1 -n <namespace>
   ```

2. Check challenges:
   ```bash
   kubectl describe challenge <challenge-name> -n <namespace>
   ```

3. Verify Cloudflare API token is valid:
   ```bash
   kubectl get secret cert-manager-secret -n cert-manager -o yaml
   ```

#### DNS-01 Challenge Failing

- Verify DNS propagation: `dig TXT _acme-challenge.yourdomain.com`
- Check Cloudflare API token permissions
- Ensure zone exists in Cloudflare

### Logs

```bash
kubectl logs -n cert-manager -l app=cert-manager
```

## Certificate Renewal

Certificates auto-renew 30 days before expiry. Monitor with:

```bash
kubectl get certificates -A -o custom-columns='NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter'
```
