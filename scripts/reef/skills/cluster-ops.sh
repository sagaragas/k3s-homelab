#!/usr/bin/env bash
# Skill: cluster-ops — deep cluster analysis and autonomous fixes (uses droid)
set -euo pipefail

REEF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="/root/homelab/k3s"

# Collect comprehensive cluster state
STATE_FILE=$(mktemp)
{
  echo "=== NODES ==="
  kubectl get nodes -o wide 2>&1
  echo ""
  echo "=== UNHEALTHY PODS ==="
  kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' --no-headers 2>&1 || echo "none"
  echo ""
  echo "=== POD RESTARTS (>3) ==="
  kubectl get pods -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.containerStatuses != null) |
      .status.containerStatuses[] | select(.restartCount > 3) |
      "\(.name) restarts=\(.restartCount)"' 2>&1 || echo "none"
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
  echo "=== RECENT WARNING EVENTS ==="
  kubectl get events -A --sort-by='.lastTimestamp' --field-selector type=Warning 2>&1 | tail -30
  echo ""
  echo "=== PVC STATUS ==="
  kubectl get pvc -A 2>&1
  echo ""
  echo "=== CERTIFICATES ==="
  kubectl get certificates -A 2>&1 || echo "none"
  echo ""
  echo "=== CEPH STATUS ==="
  kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status 2>&1 || echo "no ceph tools"
} > "$STATE_FILE" 2>&1

# Build prompt with full memory context
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << PROMPT
$(cat "$REEF_DIR/memory/SOUL.md")

## Your Long-Term Memory
$(cat "$REEF_DIR/memory/MEMORY.md")

## Current Heartbeat
$(cat "$REEF_DIR/memory/HEARTBEAT.md")

## Cluster State
$(cat "$STATE_FILE")

## Mission
1. Analyze the cluster state above
2. Fix any problems you find:
   - Runtime fixes: kubectl restart, flux reconcile, delete stuck resources
   - Manifest fixes: create a PR to sagaragas/k3s-homelab
   - Unfixable: create a GitHub issue
3. Update the memory files if you learned something new:
   - Write to $REEF_DIR/memory/MEMORY.md if there's a new pattern or incident
   - Write to $REEF_DIR/memory/HEARTBEAT.md with current status and priorities
4. Output a brief summary of what you found and what you did
PROMPT

export DISCORD_WEBHOOK
RESULT=$(droid exec --skip-permissions-unsafe \
  -m claude-opus-4-6 -r max \
  --cwd "$REPO_DIR" \
  -f "$PROMPT_FILE" 2>&1) || true

rm -f "$STATE_FILE" "$PROMPT_FILE"

# Check if droid reported problems
if echo "$RESULT" | grep -qiE '(fixed|restarted|reconciled|created pr|created issue)'; then
  echo "STATUS:ACTION"
else
  echo "STATUS:OK"
fi
echo "$RESULT"
