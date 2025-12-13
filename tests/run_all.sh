#!/usr/bin/env bash
set -euo pipefail

# Run All Tests
# Executes all validation test suites

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  k3s-homelab Test Suite"
echo "=========================================="
echo ""

FAILED=0

# Run YAML lint tests
echo ">>> Running YAML Lint Tests..."
if "${SCRIPT_DIR}/test_yaml.sh"; then
    echo "✓ YAML Lint: PASSED"
else
    echo "✗ YAML Lint: FAILED"
    FAILED=1
fi
echo ""

# Run schema validation tests
echo ">>> Running Schema Validation Tests..."
if "${SCRIPT_DIR}/test_schema.sh"; then
    echo "✓ Schema Validation: PASSED"
else
    echo "✗ Schema Validation: FAILED"
    FAILED=1
fi
echo ""

# Run Flux validation tests
echo ">>> Running Flux Validation Tests..."
if "${SCRIPT_DIR}/test_flux.sh"; then
    echo "✓ Flux Validation: PASSED"
else
    echo "✗ Flux Validation: FAILED"
    FAILED=1
fi
echo ""

echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo "  ALL TESTS PASSED"
    echo "=========================================="
    exit 0
else
    echo "  SOME TESTS FAILED"
    echo "=========================================="
    exit 1
fi
