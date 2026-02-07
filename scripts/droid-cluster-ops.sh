#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/root/homelab/k3s"
REPO="sagaragas/k3s-homelab"
LOG_DIR="/var/log/droid"
LOCK_FILE="/tmp/droid-cluster-ops.lock"

export SOPS_AGE_KEY_FILE="${REPO_DIR}/age.key"
DISCORD_WEBHOOK=$(sops -d "${REPO_DIR}/kubernetes/apps/default/cluster-maintenance/app/secret.sops.yaml" 2>/dev/null | grep 'DISCORD_WEBHOOK:' | awk '{print $2}')

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/cluster-ops-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE")
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Another cluster-ops run is active (PID $LOCK_PID), exiting"
    exit 0
  fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

echo "=== Droid Cluster Ops - $(date) ==="

# Collect cluster state
STATE_FILE=$(mktemp)
{
  echo "=== NODES ==="
  kubectl get nodes -o wide 2>&1
  echo ""
  echo "=== UNHEALTHY PODS ==="
  kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>&1
  echo ""
  echo "=== POD RESTARTS (>3) ==="
  kubectl get pods -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.containerStatuses != null) |
      .status.containerStatuses[] | select(.restartCount > 3) |
      "\(.name) ns=\(.state | keys[0]) restarts=\(.restartCount)"' 2>&1 || echo "none"
  echo ""
  echo "=== HELMRELEASES ==="
  kubectl get hr -A 2>&1
  echo ""
  echo "=== FAILED HELMRELEASES ==="
  kubectl get hr -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True")) |
      "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[] | select(.type=="Ready") | .message)"' 2>&1 || echo "none"
  echo ""
  echo "=== FLUX KUSTOMIZATIONS ==="
  flux get ks -A 2>&1
  echo ""
  echo "=== FAILED KUSTOMIZATIONS ==="
  flux get ks -A 2>&1 | grep -i false || echo "none"
  echo ""
  echo "=== RECENT EVENTS (warnings) ==="
  kubectl get events -A --sort-by='.lastTimestamp' --field-selector type=Warning 2>&1 | tail -30
  echo ""
  echo "=== PVC STATUS ==="
  kubectl get pvc -A 2>&1
  echo ""
  echo "=== CERTIFICATE STATUS ==="
  kubectl get certificates -A 2>&1 || echo "no cert-manager CRDs"
  echo ""
  echo "=== CEPH STATUS ==="
  kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status 2>&1 || echo "no ceph tools pod"
} > "$STATE_FILE" 2>&1

echo "Cluster state collected ($(wc -l < "$STATE_FILE") lines)"

# Build the ops prompt
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << 'PROMPT'
You are an expert Kubernetes/GitOps SRE operating a homelab Talos Linux cluster.

## Cluster State
The full cluster state dump is in: STATEFILE_PLACEHOLDER

## Repository
Working directory: /root/homelab/k3s (Flux GitOps repo)
GitHub repo: sagaragas/k3s-homelab

## Available Tools
- kubectl (full cluster access)
- flux (GitOps CLI)
- gh (GitHub CLI, authenticated)
- git (repo access)

## Your Mission
1. Read the cluster state file
2. Identify any problems: stuck pods, failed HelmReleases, unhealthy nodes, failing Flux reconciliations, storage issues
3. For each problem:
   - **Runtime fixes**: Use kubectl directly (restart pods, force-reconcile HRs, delete stuck resources)
   - **Manifest fixes**: Create a PR with the fix (bad image tags, wrong config values)
   - **Unfixable**: Create a GitHub issue describing the problem
4. After all fixes, send ONE Discord summary via curl to the DISCORD_WEBHOOK env var

## Safety Rules
- NEVER delete namespaces or PVCs
- NEVER drain or cordon nodes
- NEVER modify SOPS-encrypted secrets
- ALWAYS create PRs for manifest changes (never push directly to main)
- Restarting pods and force-reconciling HRs is always safe

## Output
Summarize what you found and what you did. If everything is healthy, just say so.
PROMPT

sed -i "s|STATEFILE_PLACEHOLDER|${STATE_FILE}|g" "$PROMPT_FILE"

# Export Discord webhook for droid to use
export DISCORD_WEBHOOK

# Run droid with full autonomy
echo "Running droid cluster ops review..."
droid exec --skip-permissions-unsafe \
  -m claude-opus-4-6 -r max \
  --cwd "$REPO_DIR" \
  -f "$PROMPT_FILE" 2>&1 || true

echo ""
echo "=== Cluster ops complete - $(date) ==="

rm -f "$STATE_FILE" "$PROMPT_FILE"

# Cleanup old logs (keep 30 days)
find "$LOG_DIR" -name "cluster-ops-*.log" -mtime +30 -delete 2>/dev/null || true
