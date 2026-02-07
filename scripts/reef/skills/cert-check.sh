#!/usr/bin/env bash
# Skill: cert-check — certificate expiry status (no droid)
set -euo pipefail

PROBLEMS=()

# Check cert-manager certificates
CERTS=$(kubectl get certificates -A -o json 2>/dev/null || echo '{"items":[]}')
CERT_COUNT=$(echo "$CERTS" | jq '.items | length')

if [ "$CERT_COUNT" -eq 0 ]; then
  echo "STATUS:OK"
  echo "No certificates found (cert-manager may not be installed)"
  exit 0
fi

# Find not-ready certificates
NOT_READY=$(echo "$CERTS" | jq -r '.items[] |
  select(.status.conditions[]? | select(.type=="Ready" and .status!="True")) |
  "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[] |
  select(.type=="Ready") | .message)"' 2>/dev/null || true)
if [ -n "$NOT_READY" ]; then
  PROBLEMS+=("CERTIFICATES NOT READY:\n$NOT_READY")
fi

# Find certificates expiring within 14 days
EXPIRING=$(echo "$CERTS" | jq -r --arg cutoff "$(date -u -d '+14 days' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+14d +%Y-%m-%dT%H:%M:%SZ)" \
  '.items[] | select(.status.notAfter != null) |
  select(.status.notAfter < $cutoff) |
  "\(.metadata.namespace)/\(.metadata.name) expires \(.status.notAfter)"' 2>/dev/null || true)
if [ -n "$EXPIRING" ]; then
  PROBLEMS+=("CERTIFICATES EXPIRING SOON:\n$EXPIRING")
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "STATUS:OK"
  echo "$CERT_COUNT certificates all healthy"
else
  echo "STATUS:PROBLEM"
  for p in "${PROBLEMS[@]}"; do
    echo -e "$p"
    echo ""
  done
fi
