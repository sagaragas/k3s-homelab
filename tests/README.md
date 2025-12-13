# Tests

This directory contains validation tests for the k3s-homelab infrastructure repository.

## Running Tests

```bash
# Run all tests
task test

# Run individual test suites
task test:yaml      # YAML lint validation
task test:schema    # Kubernetes schema validation
task test:flux      # Flux configuration validation
```

## Test Suites

### YAML Lint (`test_yaml.sh`)
Validates all YAML files against yamllint rules defined in `.yamllint.yaml`.

### Schema Validation (`test_schema.sh`)
Uses kubeconform to validate Kubernetes manifests against official schemas.

### Flux Validation (`test_flux.sh`)
Uses flux-local to validate Flux Kustomizations and HelmReleases.

## CI Integration

These tests run automatically in GitHub Actions on every PR via the Validate workflow.
