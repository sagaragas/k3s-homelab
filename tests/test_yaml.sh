#!/usr/bin/env bash
set -euo pipefail

# YAML Lint Test Suite
# Validates YAML syntax and style across the repository

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== YAML Lint Test Suite ==="
echo "Repository: ${REPO_ROOT}"
echo ""

# Check if yamllint is available
if ! command -v yamllint &> /dev/null; then
    echo "ERROR: yamllint not found. Install with: pip install yamllint"
    exit 1
fi

# Run yamllint
echo "Running yamllint on kubernetes/ directory..."
yamllint -c "${REPO_ROOT}/.yamllint.yaml" "${REPO_ROOT}/kubernetes/" || {
    echo "FAILED: YAML lint errors found"
    exit 1
}

echo ""
echo "PASSED: All YAML files are valid"
