# Runbook: Certificate Issues

## Symptoms

- Browser shows certificate errors
- `NET::ERR_CERT_AUTHORITY_INVALID`
- `Certificate has expired`
- Services unreachable via HTTPS

## Quick Check

```bash
# Check certificate status
kubectl get certificates -A

# Check certificate details
kubectl describe certificate <name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

## Diagnosis

### 1. Certificate Not Ready

```bash
# Check certificate status
kubectl get certificate -A
# Look for Ready=False

# Check events
kubectl describe certificate <name> -n <namespace>
```

### 2. Challenge Failed

```bash
# Check challenges
kubectl get challenges -A

# Check challenge details
kubectl describe challenge <name> -n <namespace>
```

### 3. Issuer Problems

```bash
# Check cluster issuers
kubectl get clusterissuer

# Check issuer status
kubectl describe clusterissuer letsencrypt-production
```

## Recovery Procedures

### Scenario 1: DNS Challenge Failing

```bash
# Check Cloudflare API token
kubectl get secret -n cert-manager cloudflare-api-token -o yaml

# Verify token has correct permissions:
# - Zone:DNS:Edit
# - Zone:Zone:Read

# Test DNS propagation
dig _acme-challenge.myapp.ragas.cc TXT
```

### Scenario 2: Rate Limited

Let's Encrypt rate limits:
- 50 certificates per week per domain
- 5 failures per hour per account

```bash
# Check for rate limit errors
kubectl logs -n cert-manager -l app=cert-manager | grep -i "rate limit"

# Wait and retry, or use staging issuer
```

### Scenario 3: Certificate Expired

```bash
# Delete and recreate certificate
kubectl delete certificate <name> -n <namespace>

# cert-manager will recreate automatically
# Or trigger reconciliation
kubectl annotate certificate <name> -n <namespace> \
  cert-manager.io/issuer-kind- \
  cert-manager.io/issuer-kind=ClusterIssuer
```

### Scenario 4: Secret Missing

```bash
# Check if secret exists
kubectl get secret <cert-secret-name> -n <namespace>

# If missing, delete certificate to trigger recreation
kubectl delete certificate <name> -n <namespace>
```

### Scenario 5: Wrong Certificate Served

```bash
# Check which cert the gateway is using
kubectl get gateway -n network -o yaml | grep secretName

# Verify certificate matches hostname
openssl s_client -connect myapp.ragas.cc:443 -servername myapp.ragas.cc 2>/dev/null | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
```

## Manual Certificate Renewal

```bash
# Force renewal by deleting the secret
kubectl delete secret <cert-secret-name> -n <namespace>

# cert-manager will issue a new certificate
kubectl get certificate -n <namespace> -w
```

## Using Staging Issuer

For testing, use Let's Encrypt staging:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: your@email.com
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

## Prevention

- Monitor certificate expiry with Prometheus
- Set up alerts for expiring certificates
- Use wildcard certificates to reduce rate limit risk
- Test with staging before production
