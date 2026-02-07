#!/usr/bin/env bash
# Skill: flux-sync — check Flux kustomizations and helmreleases (no droid)
set -euo pipefail

PROBLEMS=()

# Check failed kustomizations (READY column is 5th, must be True)
FAILED_KS=$(flux get ks -A 2>/dev/null | awk 'NR>1 && $5!="True"' || true)
if [ -n "$FAILED_KS" ]; then
  PROBLEMS+=("FAILED KUSTOMIZATIONS:\n$FAILED_KS")
fi

# Check failed helmreleases
FAILED_HR=$(kubectl get hr -A -o json 2>/dev/null | \
  jq -r '.items[] | select(.status.conditions[]? |
    select(.type=="Ready" and .status!="True")) |
    "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[] |
    select(.type=="Ready") | .message)"' 2>/dev/null || true)
if [ -n "$FAILED_HR" ]; then
  PROBLEMS+=("FAILED HELMRELEASES:\n$FAILED_HR")
fi

# Check suspended resources
SUSPENDED=$(flux get ks -A --no-header 2>/dev/null | grep -i "true.*suspended" || true)
if [ -n "$SUSPENDED" ]; then
  PROBLEMS+=("SUSPENDED KUSTOMIZATIONS:\n$SUSPENDED")
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "STATUS:OK"
  echo "All Flux kustomizations and HelmReleases reconciled"
else
  echo "STATUS:PROBLEM"
  for p in "${PROBLEMS[@]}"; do
    echo -e "$p"
    echo ""
  done
fi
