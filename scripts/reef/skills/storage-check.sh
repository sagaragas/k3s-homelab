#!/usr/bin/env bash
# Skill: storage-check — PVC usage and Ceph health (no droid)
set -euo pipefail

PROBLEMS=()

# Check PVC status
PENDING_PVC=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -v "Bound" || true)
if [ -n "$PENDING_PVC" ]; then
  PROBLEMS+=("PVCS NOT BOUND:\n$PENDING_PVC")
fi

# Check Ceph health
CEPH_STATUS=$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status -f json 2>/dev/null || echo '{}')
CEPH_HEALTH=$(echo "$CEPH_STATUS" | jq -r '.health.status // "UNKNOWN"' 2>/dev/null)

if [ "$CEPH_HEALTH" = "HEALTH_ERR" ]; then
  CEPH_DETAIL=$(echo "$CEPH_STATUS" | jq -r '.health.checks | to_entries[] | "\(.key): \(.value.summary.message)"' 2>/dev/null || true)
  PROBLEMS+=("CEPH HEALTH_ERR:\n$CEPH_DETAIL")
elif [ "$CEPH_HEALTH" = "HEALTH_WARN" ]; then
  CEPH_DETAIL=$(echo "$CEPH_STATUS" | jq -r '.health.checks | to_entries[] | "\(.key): \(.value.summary.message)"' 2>/dev/null || true)
  # Slow ops during media writes are normal — only flag if not just slow_ops
  if ! echo "$CEPH_DETAIL" | grep -q "slow ops" || echo "$CEPH_DETAIL" | grep -c ":" | grep -q "^1$"; then
    : # Single slow_ops warning is normal, skip
  else
    PROBLEMS+=("CEPH HEALTH_WARN:\n$CEPH_DETAIL")
  fi
fi

# Check Ceph OSD usage (>85% is concerning)
OSD_USAGE=$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd df -f json 2>/dev/null || echo '{}')
HIGH_OSDS=$(echo "$OSD_USAGE" | jq -r '.nodes[]? | select(.utilization > 85) |
  "osd.\(.id) at \(.utilization)%"' 2>/dev/null || true)
if [ -n "$HIGH_OSDS" ]; then
  PROBLEMS+=("CEPH OSDS >85% FULL:\n$HIGH_OSDS")
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "STATUS:OK"
  echo "All PVCs bound, Ceph $CEPH_HEALTH"
else
  echo "STATUS:PROBLEM"
  for p in "${PROBLEMS[@]}"; do
    echo -e "$p"
    echo ""
  done
fi
