#!/usr/bin/env bash
# Skill: daily-briefing — compose and send morning summary to Discord (uses droid)
set -euo pipefail

REEF_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Collect stats for the briefing
STATS_FILE=$(mktemp)
{
  echo "=== NODE STATUS ==="
  kubectl get nodes --no-headers 2>&1
  echo ""
  echo "=== POD SUMMARY ==="
  echo "Total: $(kubectl get pods -A --no-headers 2>/dev/null | wc -l)"
  echo "Running: $(kubectl get pods -A --no-headers --field-selector=status.phase=Running 2>/dev/null | wc -l)"
  echo "Failed: $(kubectl get pods -A --no-headers --field-selector=status.phase=Failed 2>/dev/null | wc -l)"
  echo ""
  echo "=== FLUX STATUS ==="
  flux get ks -A --no-header 2>&1 | head -20
  echo ""
  echo "=== HELMRELEASES ==="
  kubectl get hr -A --no-headers 2>&1 | head -20
  echo ""
  echo "=== OPEN PRS ==="
  gh pr list --repo sagaragas/k3s-homelab --state open --json number,title,author --jq '.[] | "#\(.number) \(.title) (by \(.author.login))"' 2>&1 || echo "none"
  echo ""
  echo "=== CEPH HEALTH ==="
  kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status 2>&1 | head -10 || echo "unknown"
  echo ""
  echo "=== CERTIFICATES ==="
  kubectl get certificates -A --no-headers 2>&1 | head -10 || echo "none"
  echo ""
  echo "=== RECENT REEF LOG ==="
  cat "$REEF_DIR/memory/logs/$(date +%Y-%m-%d).md" 2>/dev/null | tail -30 || echo "no log yet"
} > "$STATS_FILE" 2>&1

PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << PROMPT
You are Reef, the autonomous cluster agent. Compose a morning briefing for Discord.

## Current Stats
$(cat "$STATS_FILE")

## Recent Memory
$(cat "$REEF_DIR/memory/HEARTBEAT.md")

## Task
Write a concise Discord-formatted briefing. Use this structure:
- One-line overall status (green/yellow/red)
- Nodes: X/Y ready
- Pods: X running, Y failed
- Flux: X kustomizations, Y helmreleases, any failures
- Ceph: health status
- PRs: X open, list them briefly
- Actions taken since last briefing (from heartbeat/logs)

Keep it short and scannable. Use bullet points. No fluff.
Output ONLY the briefing text, nothing else.
PROMPT

BRIEFING=$(droid exec -m claude-opus-4-6 -r low \
  -f "$PROMPT_FILE" 2>&1) || true

rm -f "$STATS_FILE" "$PROMPT_FILE"

# Send to Discord
if [ -n "$DISCORD_WEBHOOK" ] && [ -n "$BRIEFING" ]; then
  # Truncate to Discord embed limit
  BRIEFING_TRUNC=$(echo "$BRIEFING" | head -c 4000)
  curl -sf -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"Reef Daily Briefing\",\"description\":$(echo "$BRIEFING_TRUNC" | jq -Rs .),\"color\":3447003,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}" \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
fi

echo "STATUS:OK"
echo "Daily briefing sent to Discord"
