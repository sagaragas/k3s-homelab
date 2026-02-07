#!/usr/bin/env bash
set -euo pipefail

REEF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="/root/homelab/k3s"
LOG_DIR="/var/log/reef"
LOCK_FILE="/tmp/reef.lock"

export SOPS_AGE_KEY_FILE="${REPO_DIR}/age.key"
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export HOME="/root"

# Decrypt Discord webhook once at startup
export DISCORD_WEBHOOK
DISCORD_WEBHOOK=$(sops -d "${REPO_DIR}/kubernetes/apps/default/cluster-maintenance/app/secret.sops.yaml" 2>/dev/null | grep 'DISCORD_WEBHOOK:' | awk '{print $2}')

mkdir -p "$LOG_DIR" "$REEF_DIR/memory/logs"

# ── Lock ──────────────────────────────────────────────────
if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || true)
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Reef already running (PID $LOCK_PID), exiting"
    exit 0
  fi
fi
echo $$ > "$LOCK_FILE"
cleanup() { rm -f "$LOCK_FILE"; }
trap cleanup EXIT INT TERM

# ── Skill Schedule ────────────────────────────────────────
# skill_name:interval_seconds
declare -A SKILL_INTERVALS=(
  [cluster-health]=300       # 5 min
  [flux-sync]=900            # 15 min
  [pr-gatekeeper]=900        # 15 min
  [cert-check]=3600          # 1 hour
  [storage-check]=3600       # 1 hour
  [security-audit]=86400     # daily
  [cluster-ops]=21600        # 6 hours
  [daily-briefing]=86400     # daily
)

# Fixed schedule for daily skills (hour of day, 24h format)
declare -A SKILL_FIXED_HOUR=(
  [daily-briefing]=8         # 8am
  [security-audit]=2         # 2am
)

# Track last run time for each skill
declare -A LAST_RUN
for skill in "${!SKILL_INTERVALS[@]}"; do
  LAST_RUN[$skill]=0
done

# ── Helpers ───────────────────────────────────────────────
log() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $*" | tee -a "$LOG_DIR/reef.log"
}

daily_log() {
  local today
  today=$(date +%Y-%m-%d)
  local logfile="$REEF_DIR/memory/logs/${today}.md"
  if [ ! -f "$logfile" ]; then
    echo "# Reef Log — $today" > "$logfile"
    echo "" >> "$logfile"
  fi
  echo "- $(date +%H:%M) $*" >> "$logfile"
}

discord_notify() {
  local title="$1" desc="$2" color="${3:-3066993}"
  [ -z "${DISCORD_WEBHOOK:-}" ] && return 0
  local desc_json
  desc_json=$(echo "$desc" | head -c 4000 | jq -Rs .)
  curl -sf -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"${title}\",\"description\":${desc_json},\"color\":${color},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}" \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
}

run_skill() {
  local skill="$1"
  local script="$REEF_DIR/skills/${skill}.sh"

  if [ ! -x "$script" ]; then
    log "WARN: skill $skill not found at $script"
    return
  fi

  log "Running skill: $skill"
  local output
  output=$("$script" 2>&1) || true
  local status
  status=$(echo "$output" | head -1)
  local details
  details=$(echo "$output" | tail -n +2)

  LAST_RUN[$skill]=$(date +%s)

  case "$status" in
    STATUS:OK)
      log "  $skill: OK — $(echo "$details" | head -1)"
      daily_log "$skill: OK"
      ;;
    STATUS:PROBLEM)
      log "  $skill: PROBLEM detected"
      daily_log "$skill: PROBLEM — $(echo "$details" | head -3 | tr '\n' ' ')"

      # For non-droid skills that find problems, invoke droid to fix
      if [[ "$skill" != "pr-gatekeeper" && "$skill" != "cluster-ops" && "$skill" != "daily-briefing" ]]; then
        log "  Invoking droid to analyze and fix: $skill"
        local fix_prompt
        fix_prompt=$(mktemp)
        cat > "$fix_prompt" << PROMPT
$(cat "$REEF_DIR/memory/SOUL.md" | head -50)

## Problem Detected by $skill skill

$details

## Your Long-Term Memory
$(cat "$REEF_DIR/memory/MEMORY.md" | tail -30)

## Task
1. Analyze the problem above
2. Fix it if possible (kubectl restart, flux reconcile, etc.)
3. If it needs a manifest fix, create a PR
4. If unfixable, create a GitHub issue
5. Update $REEF_DIR/memory/MEMORY.md if you learned something new
6. Update $REEF_DIR/memory/HEARTBEAT.md with current status
7. Output a brief summary of what you did
PROMPT
        local fix_result
        fix_result=$(droid exec --skip-permissions-unsafe \
          -m claude-opus-4-6 -r max \
          --cwd "$REPO_DIR" \
          -f "$fix_prompt" 2>&1) || true
        rm -f "$fix_prompt"

        log "  Droid result: $(echo "$fix_result" | head -3)"
        daily_log "  droid fix attempt: $(echo "$fix_result" | head -1)"

        discord_notify \
          "Reef: $skill detected issue" \
          "**Problem:**\n$(echo "$details" | head -c 500)\n\n**Action:**\n$(echo "$fix_result" | head -c 500)" \
          15105570  # orange
      fi
      ;;
    STATUS:ACTION)
      log "  $skill: action taken"
      daily_log "$skill: $(echo "$details" | head -3 | tr '\n' ' ')"

      # Notify Discord for PR merges
      if [ "$skill" = "pr-gatekeeper" ]; then
        local merged
        merged=$(echo "$details" | head -1)
        if echo "$merged" | grep -q "merged=[^0]"; then
          discord_notify \
            "Reef: PRs merged" \
            "$(echo "$details" | head -c 1000)" \
            3066993  # green
        fi
      fi
      ;;
  esac
}

should_run() {
  local skill="$1"
  local now
  now=$(date +%s)
  local interval=${SKILL_INTERVALS[$skill]}
  local last=${LAST_RUN[$skill]}

  # Check fixed-hour skills
  if [[ -v "SKILL_FIXED_HOUR[$skill]" ]]; then
    local target_hour=${SKILL_FIXED_HOUR[$skill]}
    local current_hour
    current_hour=$(date +%-H)
    local today
    today=$(date +%Y-%m-%d)
    local last_run_day=""
    if [ "$last" -gt 0 ]; then
      last_run_day=$(date -d "@$last" +%Y-%m-%d 2>/dev/null || date -r "$last" +%Y-%m-%d 2>/dev/null || true)
    fi

    # Run if it's the target hour and hasn't run today
    if [ "$current_hour" -eq "$target_hour" ] && [ "$last_run_day" != "$today" ]; then
      return 0
    fi
    return 1
  fi

  # Interval-based skills
  local elapsed=$((now - last))
  if [ "$elapsed" -ge "$interval" ]; then
    return 0
  fi
  return 1
}

# ── Main Loop ─────────────────────────────────────────────
log "=== Reef starting (PID $$) ==="
log "Skills: ${!SKILL_INTERVALS[*]}"
daily_log "Reef started (PID $$)"

# Startup notification
discord_notify \
  "Reef Online" \
  "Autonomous cluster agent started.\nSkills: ${!SKILL_INTERVALS[*]}" \
  3066993

# Run cluster-health immediately on startup
run_skill "cluster-health"

while true; do
  for skill in cluster-health flux-sync pr-gatekeeper cert-check storage-check security-audit cluster-ops daily-briefing; do
    if should_run "$skill"; then
      run_skill "$skill"
    fi
  done

  # Rotate old daily logs (keep 30 days)
  find "$REEF_DIR/memory/logs" -name "*.md" -mtime +30 -delete 2>/dev/null || true

  # Rotate main log (keep 10MB)
  if [ -f "$LOG_DIR/reef.log" ] && [ "$(stat -c%s "$LOG_DIR/reef.log" 2>/dev/null || echo 0)" -gt 10485760 ]; then
    mv "$LOG_DIR/reef.log" "$LOG_DIR/reef.log.old"
  fi

  # Sleep 60s between cycles
  sleep 60
done
