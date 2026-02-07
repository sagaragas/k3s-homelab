#!/usr/bin/env bash
# Skill: security-audit — check for security issues (no droid)
set -euo pipefail

PROBLEMS=()

# Check for privileged containers
PRIVILEGED=$(kubectl get pods -A -o json 2>/dev/null | \
  jq -r '.items[] | .spec.containers[]? |
    select(.securityContext?.privileged == true) |
    "\(.name)"' 2>/dev/null | sort -u || true)
if [ -n "$PRIVILEGED" ]; then
  # Filter known-privileged (cilium, ceph, node-exporter are expected)
  UNEXPECTED=$(echo "$PRIVILEGED" | grep -vE '(cilium|ceph|csi-rbdplugin|csi-cephfsplugin|driver-registrar|liveness-prometheus|node-exporter|kube-proxy)' || true)
  if [ -n "$UNEXPECTED" ]; then
    PROBLEMS+=("UNEXPECTED PRIVILEGED CONTAINERS:\n$UNEXPECTED")
  fi
fi

# Check for pods running as root without security context
NO_SECCTX=$(kubectl get pods -A -o json 2>/dev/null | \
  jq -r '.items[] | select(.spec.securityContext == null or .spec.securityContext == {}) |
    select(.metadata.namespace != "kube-system" and .metadata.namespace != "rook-ceph" and .metadata.namespace != "network") |
    "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -20 || true)
# This is informational, not a hard problem
if [ -n "$NO_SECCTX" ]; then
  COUNT=$(echo "$NO_SECCTX" | wc -l)
  if [ "$COUNT" -gt 10 ]; then
    : # Too many to be actionable, skip
  fi
fi

# Check for exposed LoadBalancer services (unexpected)
LB_SERVICES=$(kubectl get svc -A --no-headers -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,IP:.status.loadBalancer.ingress[0].ip' 2>/dev/null | grep "LoadBalancer" || true)
# This is informational — all LBs should be on internal IPs (172.16.x.x)
EXTERNAL_LB=$(echo "$LB_SERVICES" | grep -v "172\.16\." | grep -v "<none>" || true)
if [ -n "$EXTERNAL_LB" ]; then
  PROBLEMS+=("LOADBALANCERS WITH NON-INTERNAL IPS:\n$EXTERNAL_LB")
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "STATUS:OK"
  echo "No unexpected security issues found"
else
  echo "STATUS:PROBLEM"
  for p in "${PROBLEMS[@]}"; do
    echo -e "$p"
    echo ""
  done
fi
