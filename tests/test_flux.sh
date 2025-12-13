#!/usr/bin/env bash
set -euo pipefail

# Flux Configuration Validation Test Suite
# Validates Flux Kustomizations and HelmReleases using flux-local

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Flux Configuration Validation Test Suite ==="
echo "Repository: ${REPO_ROOT}"
echo ""

# Check if flux-local is available
if ! command -v flux-local &> /dev/null; then
    echo "ERROR: flux-local not found. Install with: pip install flux-local"
    exit 1
fi

# Run flux-local test
echo "Running flux-local validation on kubernetes/flux..."
flux-local test --path "${REPO_ROOT}/kubernetes/flux" --enable-helm || {
    echo "FAILED: Flux configuration errors found"
    exit 1
}

echo ""
echo "PASSED: All Flux configurations are valid"
