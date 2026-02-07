#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/root/homelab/k3s"
REPO="sagaragas/k3s-homelab"
LOG_DIR="/var/log/droid"
LOCK_FILE="/tmp/droid-gatekeeper.lock"

export SOPS_AGE_KEY_FILE="${REPO_DIR}/age.key"
DISCORD_WEBHOOK=$(sops -d "${REPO_DIR}/kubernetes/apps/default/cluster-maintenance/app/secret.sops.yaml" 2>/dev/null | grep 'DISCORD_WEBHOOK:' | awk '{print $2}')

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/gatekeeper-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE")
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Another gatekeeper run is active (PID $LOCK_PID), exiting"
    exit 0
  fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

TRUSTED_AUTHORS="renovate[bot] dependabot[bot] factory-droid[bot] app/renovate"

is_trusted() {
  local author="$1"
  for bot in $TRUSTED_AUTHORS; do
    [ "$author" = "$bot" ] && return 0
  done
  return 1
}

is_critical() {
  local title="$1"
  echo "$title" | grep -qiE '(talos|cilium|postgres.*major|etcd|ceph)'
}

discord_notify() {
  local title="$1" desc="$2" color="${3:-3066993}"
  [ -z "$DISCORD_WEBHOOK" ] && return 0
  curl -sf -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"${title}\",\"description\":\"${desc}\",\"color\":${color},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}" \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
}

echo "=== Droid PR Gatekeeper - $(date) ==="

cd "$REPO_DIR"
git fetch origin main --quiet

# Get all open PRs where CI has passed
OPEN_PRS=$(gh pr list --repo "$REPO" --state open \
  --json number,title,author,headRefName,statusCheckRollup \
  --jq '.[] | select(.statusCheckRollup | length > 0) |
    select([.statusCheckRollup[] | select(.name != "Droid PR Gatekeeper")] |
      all(.conclusion == "SUCCESS" or .conclusion == "SKIPPED" or .conclusion == "NEUTRAL")) |
    "\(.number)\t\(.author.login)\t\(.title)"')

if [ -z "$OPEN_PRS" ]; then
  echo "No PRs with passing CI found"
  exit 0
fi

MERGED=0
FLAGGED=0

while IFS=$'\t' read -r PR_NUMBER PR_AUTHOR PR_TITLE; do
  echo ""
  echo "--- PR #${PR_NUMBER}: ${PR_TITLE} (by ${PR_AUTHOR}) ---"

  # Get the diff
  DIFF_FILE=$(mktemp)
  gh pr diff "$PR_NUMBER" --repo "$REPO" > "$DIFF_FILE" 2>&1 || true

  if [ ! -s "$DIFF_FILE" ]; then
    echo "  Empty diff, skipping"
    rm -f "$DIFF_FILE"
    continue
  fi

  # Build review prompt
  PROMPT_FILE=$(mktemp)
  cat > "$PROMPT_FILE" << PROMPT
You are a Kubernetes/GitOps expert reviewing PR #${PR_NUMBER} in a homelab cluster repository.

## PR Info
- Title: ${PR_TITLE}
- Author: ${PR_AUTHOR}
- Trusted bot: $(is_trusted "$PR_AUTHOR" && echo "true" || echo "false")
- Critical infrastructure: $(is_critical "$PR_TITLE" && echo "true" || echo "false")

## Diff
The PR diff is in: ${DIFF_FILE}

## Your Task
1. Read the diff file
2. Check for breaking changes, security issues, config errors, resource issues
3. Output EXACTLY one of these as the LAST line:
   - DECISION: APPROVE
   - DECISION: REJECT
   - DECISION: FLAG

Be pragmatic. Dependency bumps from Renovate are almost always safe.
Focus on real bugs and breaking changes, not style.
PROMPT

  # Run droid review
  REVIEW_OUTPUT=$(droid exec --skip-permissions-unsafe \
    -m claude-opus-4-6 -r max \
    -f "$PROMPT_FILE" 2>&1) || true

  DECISION=$(echo "$REVIEW_OUTPUT" | grep -oE 'DECISION: (APPROVE|REJECT|FLAG)' | tail -1 | awk '{print $2}')
  [ -z "$DECISION" ] && DECISION="FLAG"

  echo "  Decision: $DECISION"

  case "$DECISION" in
    APPROVE)
      if is_critical "$PR_TITLE"; then
        echo "  Critical infra -- leaving for human merge"
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "## Droid Gatekeeper: Approved (Critical Infra)
Changes look safe, but this touches critical infrastructure. Leaving for human merge." || true
        FLAGGED=$((FLAGGED+1))

      elif is_trusted "$PR_AUTHOR"; then
        echo "  Trusted bot -- auto-merging"
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "## Droid Gatekeeper: Approved -- auto-merging

$(echo "$REVIEW_OUTPUT" | head -c 60000)" || true

        if gh pr merge "$PR_NUMBER" --repo "$REPO" --squash --delete-branch 2>&1; then
          MERGED=$((MERGED+1))
          discord_notify \
            "Merged PR #${PR_NUMBER}" \
            "**${PR_TITLE}**\nby ${PR_AUTHOR}\n\nAuto-reviewed and merged by Droid Gatekeeper." \
            3066993
          sleep 5
        else
          echo "  Merge failed"
        fi

      else
        echo "  Human PR -- posting review only"
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "## Droid Gatekeeper: Approved

$(echo "$REVIEW_OUTPUT" | head -c 60000)

---
CI passed, review looks good. Ready for you to merge." || true
      fi
      ;;

    REJECT)
      echo "  Issues found"
      gh pr comment "$PR_NUMBER" --repo "$REPO" \
        --body "## Droid Gatekeeper: Issues Found

$(echo "$REVIEW_OUTPUT" | head -c 60000)

---
Found problems in this PR. Please address the issues above." || true
      discord_notify \
        "PR #${PR_NUMBER} flagged" \
        "**${PR_TITLE}**\nby ${PR_AUTHOR}\n\nDroid found issues." \
        15158332
      FLAGGED=$((FLAGGED+1))
      ;;

    FLAG)
      echo "  Flagged for human review"
      gh pr comment "$PR_NUMBER" --repo "$REPO" \
        --body "## Droid Gatekeeper: Needs Human Review

$(echo "$REVIEW_OUTPUT" | head -c 60000)

---
This PR needs human attention before merging." || true
      FLAGGED=$((FLAGGED+1))
      ;;
  esac

  rm -f "$DIFF_FILE" "$PROMPT_FILE"
done <<< "$OPEN_PRS"

echo ""
echo "=== Summary: merged=$MERGED, flagged=$FLAGGED ==="

# Cleanup old logs (keep 30 days)
find "$LOG_DIR" -name "gatekeeper-*.log" -mtime +30 -delete 2>/dev/null || true
