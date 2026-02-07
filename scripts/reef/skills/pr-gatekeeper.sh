#!/usr/bin/env bash
# Skill: pr-gatekeeper — review and merge PRs with passing CI (uses droid)
set -euo pipefail

REEF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="/root/homelab/k3s"
REPO="sagaragas/k3s-homelab"

TRUSTED_AUTHORS="renovate[bot] dependabot[bot] factory-droid[bot] app/renovate"

is_trusted() {
  local author="$1"
  for bot in $TRUSTED_AUTHORS; do
    [ "$author" = "$bot" ] && return 0
  done
  return 1
}

is_critical() {
  echo "$1" | grep -qiE '(talos|cilium|postgres.*major|etcd|ceph)'
}

cd "$REPO_DIR"
git fetch origin main --quiet 2>/dev/null || true

# Find open PRs with all checks passing
OPEN_PRS=$(gh pr list --repo "$REPO" --state open \
  --json number,title,author,statusCheckRollup \
  --jq '.[] | select(.statusCheckRollup | length > 0) |
    select([.statusCheckRollup[] | select(.name != "Droid PR Gatekeeper")] |
      all(.conclusion == "SUCCESS" or .conclusion == "SKIPPED" or .conclusion == "NEUTRAL")) |
    "\(.number)\t\(.author.login)\t\(.title)"' 2>/dev/null || true)

if [ -z "$OPEN_PRS" ]; then
  echo "STATUS:OK"
  echo "No PRs with passing CI"
  exit 0
fi

MERGED=0
FLAGGED=0
DETAILS=""

while IFS=$'\t' read -r PR_NUMBER PR_AUTHOR PR_TITLE; do
  DIFF_FILE=$(mktemp)
  gh pr diff "$PR_NUMBER" --repo "$REPO" > "$DIFF_FILE" 2>&1 || true

  if [ ! -s "$DIFF_FILE" ]; then
    rm -f "$DIFF_FILE"
    continue
  fi

  # Build review prompt with memory context
  PROMPT_FILE=$(mktemp)
  cat > "$PROMPT_FILE" << PROMPT
You are Reef, an autonomous cluster agent. Review this PR.

## Memory Context
$(cat "$REEF_DIR/memory/SOUL.md" | head -40)

## PR #${PR_NUMBER}
- Title: ${PR_TITLE}
- Author: ${PR_AUTHOR}
- Trusted bot: $(is_trusted "$PR_AUTHOR" && echo "yes" || echo "no")
- Critical infra: $(is_critical "$PR_TITLE" && echo "yes" || echo "no")

## Diff
$(cat "$DIFF_FILE")

## Task
Review the diff. Check for breaking changes, security issues, config errors.
Output EXACTLY one line as the LAST line:
  DECISION: APPROVE
  DECISION: REJECT
  DECISION: FLAG
PROMPT

  REVIEW=$(droid exec --skip-permissions-unsafe -m claude-opus-4-6 -r max \
    -f "$PROMPT_FILE" 2>&1) || true
  DECISION=$(echo "$REVIEW" | grep -oE 'DECISION: (APPROVE|REJECT|FLAG)' | tail -1 | awk '{print $2}')
  [ -z "$DECISION" ] && DECISION="FLAG"

  case "$DECISION" in
    APPROVE)
      if is_critical "$PR_TITLE"; then
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "**Reef:** Approved but critical infra — leaving for human merge." 2>/dev/null || true
        DETAILS+="PR #${PR_NUMBER} (${PR_TITLE}): approved, critical infra, left for human\n"
        FLAGGED=$((FLAGGED+1))
      elif is_trusted "$PR_AUTHOR"; then
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "**Reef:** Reviewed and approved. Auto-merging." 2>/dev/null || true
        if gh pr merge "$PR_NUMBER" --repo "$REPO" --squash --delete-branch 2>/dev/null; then
          DETAILS+="PR #${PR_NUMBER} (${PR_TITLE}): merged\n"
          MERGED=$((MERGED+1))
          sleep 5
        else
          DETAILS+="PR #${PR_NUMBER} (${PR_TITLE}): approved but merge failed\n"
        fi
      else
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "**Reef:** Reviewed and approved. Ready for you to merge.\n\n$(echo "$REVIEW" | head -c 10000)" 2>/dev/null || true
        DETAILS+="PR #${PR_NUMBER} (${PR_TITLE}): approved, human PR, left for author\n"
      fi
      ;;
    REJECT)
      gh pr comment "$PR_NUMBER" --repo "$REPO" \
        --body "**Reef:** Issues found.\n\n$(echo "$REVIEW" | head -c 10000)" 2>/dev/null || true
      DETAILS+="PR #${PR_NUMBER} (${PR_TITLE}): REJECTED\n"
      FLAGGED=$((FLAGGED+1))
      ;;
    FLAG)
      gh pr comment "$PR_NUMBER" --repo "$REPO" \
        --body "**Reef:** Needs human review.\n\n$(echo "$REVIEW" | head -c 10000)" 2>/dev/null || true
      DETAILS+="PR #${PR_NUMBER} (${PR_TITLE}): flagged for human\n"
      FLAGGED=$((FLAGGED+1))
      ;;
  esac

  rm -f "$DIFF_FILE" "$PROMPT_FILE"
done <<< "$OPEN_PRS"

if [ "$MERGED" -gt 0 ] || [ "$FLAGGED" -gt 0 ]; then
  echo "STATUS:ACTION"
  echo "merged=$MERGED flagged=$FLAGGED"
  echo -e "$DETAILS"
else
  echo "STATUS:OK"
  echo "No PRs needed action"
fi
