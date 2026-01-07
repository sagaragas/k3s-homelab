#!/usr/bin/env bash
set -euo pipefail

# Kubernetes Schema Validation Test Suite
# Validates manifests against Kubernetes API schemas using kubeconform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Kubernetes Schema Validation Test Suite ==="
echo "Repository: ${REPO_ROOT}"
echo ""

# Check if kubeconform is available
if ! command -v kubeconform &> /dev/null; then
    echo "ERROR: kubeconform not found. Install from: https://github.com/yannh/kubeconform"
    exit 1
fi

# Find and validate Kubernetes manifests
echo "Running kubeconform on kubernetes/ directory..."
find "${REPO_ROOT}/kubernetes" -name '*.yaml' -type f \
    ! -name '*.sops.yaml' \
    ! -name 'kustomization.yaml' \
    ! -path '*/components/*' \
    -print0 | \
xargs -0 kubeconform \
    -strict \
    -ignore-missing-schemas \
    -skip Secret,SopsSecret \
    -kubernetes-version 1.34.0 \
    -summary || {
    echo "FAILED: Schema validation errors found"
    exit 1
}

echo ""
echo "PASSED: All manifests are valid against Kubernetes schemas"
