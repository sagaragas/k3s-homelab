#!/usr/bin/env bash
# Skill: cluster-health — lightweight node/pod health check (no droid)
# Returns: STATUS:OK or STATUS:PROBLEM with details on stdout
set -euo pipefail

PROBLEMS=()

# Check node readiness
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " || true)
if [ -n "$NOT_READY" ]; then
  PROBLEMS+=("NODES NOT READY:\n$NOT_READY")
fi

# Check for unhealthy pods (excluding completed jobs)
UNHEALTHY=$(kubectl get pods -A --no-headers --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null | grep -v "Completed" || true)
if [ -n "$UNHEALTHY" ]; then
  COUNT=$(echo "$UNHEALTHY" | wc -l)
  PROBLEMS+=("$COUNT UNHEALTHY PODS:\n$UNHEALTHY")
fi

# Check for crash-looping pods (>20 restarts — low counts are normal for long-lived infra pods)
CRASHLOOP=$(kubectl get pods -A -o json 2>/dev/null | \
  jq -r '.items[] | select(.status.containerStatuses != null) |
    .status.containerStatuses[] | select(.restartCount > 20) |
    "\(.name) restarts=\(.restartCount)"' 2>/dev/null || true)
if [ -n "$CRASHLOOP" ]; then
  PROBLEMS+=("CRASH-LOOPING PODS:\n$CRASHLOOP")
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "STATUS:OK"
  echo "All nodes ready, no unhealthy or crash-looping pods"
else
  echo "STATUS:PROBLEM"
  for p in "${PROBLEMS[@]}"; do
    echo -e "$p"
    echo ""
  done
fi
