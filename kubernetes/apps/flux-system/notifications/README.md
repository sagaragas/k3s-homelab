# Flux Notifications

This directory contains Flux notification providers and alerts.

## Setup

### GitHub Commit Status

To enable GitHub commit status updates, create a GitHub personal access token with `repo:status` scope and create the secret:

```bash
# Create the secret
kubectl create secret generic github-token \
  --namespace flux-system \
  --from-literal=token=ghp_your_token_here

# Or encrypt with SOPS and commit
cat <<EOF > secret.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-token
  namespace: flux-system
stringData:
  token: ghp_your_token_here
EOF

sops --encrypt --in-place secret.sops.yaml
```

### Discord Notifications

To enable Discord notifications:

1. Create a Discord webhook in your server
2. Uncomment the Discord provider and alert in `kustomization.yaml`
3. Create the webhook secret:

```bash
kubectl create secret generic discord-webhook \
  --namespace flux-system \
  --from-literal=address=https://discord.com/api/webhooks/...
```

### Slack Notifications

Similar to Discord, create a Slack incoming webhook and update the provider type to `slack`.

## Alert Severity

- `info` - All events (success + failure)
- `error` - Only failures

Adjust `eventSeverity` in the Alert resources as needed.
