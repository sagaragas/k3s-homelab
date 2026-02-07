#!/usr/bin/env bash
set -euo pipefail

# AGENTS.md Validation Test Suite
# Checks that AGENTS.md service inventory matches actual app directories

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_MD="${REPO_ROOT}/AGENTS.md"
APPS_ROOT="${REPO_ROOT}/kubernetes/apps"

echo "=== AGENTS.md Validation Test Suite ==="
echo "Repository: ${REPO_ROOT}"
echo ""

FAILED=0

# 1. Check AGENTS.md exists and is non-trivial
if [ ! -f "${AGENTS_MD}" ]; then
    echo "FAILED: AGENTS.md not found"
    exit 1
fi

CHAR_COUNT=$(wc -c < "${AGENTS_MD}")
if [ "${CHAR_COUNT}" -lt 100 ]; then
    echo "FAILED: AGENTS.md is too small (${CHAR_COUNT} bytes)"
    exit 1
fi
echo "✓ AGENTS.md exists (${CHAR_COUNT} bytes)"

# 2. Check deployed K8s apps in AGENTS.md have matching directories
echo ""
echo "Checking service inventory against kubernetes/apps/..."

# Extract app names listed as "Deployed" in the K8s services table
# The table has: | Service | URL | Status | Notes |
LISTED_APPS=$(grep -E '^\|.*\| ✅ Deployed' "${AGENTS_MD}" | \
    awk -F'|' '{print $2}' | \
    sed 's/^ *//;s/ *$//' | \
    sort)

# Dirs that are infrastructure, not user-facing apps
INFRA_DIRS="cluster-maintenance echo media-storage namespace.yaml"

while IFS= read -r app; do
    [ -z "${app}" ] && continue

    # Map display name to directory name
    dir_name=$(echo "${app}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    # Known mappings where display name != directory name
    case "${dir_name}" in
        "postgresql") continue ;; # lives in database/postgres
        "speedtest-tracker") dir_name="speedtest-tracker" ;;
    esac

    # Search across all namespace directories
    found=0
    for ns_dir in "${APPS_ROOT}"/*/; do
        if [ -d "${ns_dir}${dir_name}" ]; then
            found=1
            break
        fi
    done

    if [ ${found} -eq 0 ]; then
        echo "✗ AGENTS.md lists '${app}' as deployed but no matching directory found"
        FAILED=1
    fi
done <<< "${LISTED_APPS}"

# 3. Check app directories are mentioned in AGENTS.md
# Only check default/ namespace apps (monitoring/network/etc are infra)
for dir in "${APPS_ROOT}"/default/*/; do
    [ ! -d "${dir}" ] && continue
    dir_name=$(basename "${dir}")

    # Skip infrastructure dirs
    case "${dir_name}" in
        cluster-maintenance|echo|media-storage|mkdocs|apprise) continue ;;
    esac

    # Match both hyphenated and spaced forms
    search_pattern="${dir_name}"
    search_alt=$(echo "${dir_name}" | tr '-' ' ')
    if ! grep -qi "${dir_name}" "${AGENTS_MD}" && ! grep -qi "${search_alt}" "${AGENTS_MD}"; then
        echo "✗ Directory kubernetes/apps/default/${dir_name}/ exists but not listed in AGENTS.md"
        FAILED=1
    fi
done

echo ""
if [ ${FAILED} -eq 0 ]; then
    echo "PASSED: AGENTS.md service inventory is consistent"
else
    echo "FAILED: AGENTS.md is out of sync with actual deployments"
    exit 1
fi
