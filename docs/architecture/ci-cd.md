# CI/CD Architecture

This document describes the continuous integration and deployment pipeline for the homelab cluster.

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Git Push / PR                                │
└───────────────────────────┬─────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   Validate    │   │ Droid Review  │   │  Auto-Merge   │
│   Workflow    │   │  (AI Review)  │   │   Workflow    │
└───────┬───────┘   └───────────────┘   └───────────────┘
        │
┌───────┴───────┐
│   YAML Lint   │
│  Kubeconform  │◄──── On Failure ────► Droid CI Fix
│  Flux Local   │                       (Auto-repairs)
└───────┬───────┘
        │
        ▼
┌───────────────┐
│  Flux GitOps  │──────► Cluster ──────► Discord
└───────────────┘                        Notifications
```

## Automation Stack

| Component | Purpose | Trigger |
|-----------|---------|---------|
| **Validate** | YAML/K8s validation | Every push/PR |
| **Droid Review** | AI code review | PR opened |
| **Droid CI Fix** | Auto-fix failures | CI failure on branch |
| **Auto-Merge** | Merge dependency PRs | CI passes |
| **Renovate** | Dependency updates | Daily scan |
| **Flux Image Automation** | Container updates | New image tags |
| **Release Drafter** | Release notes | PR merged |

## GitHub Actions Workflows

### Validate (`validate.yaml`)

Runs on every push and PR to ensure code quality.

| Job | Purpose |
|-----|---------|
| **YAML Lint** | Validates YAML syntax and style |
| **Kubeconform** | Validates Kubernetes manifests against schemas |
| **Flux Local** | Tests Flux Kustomizations offline |

```yaml
# Triggered on
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

### Auto-Merge (`auto-merge.yaml`)

Automatically merges Dependabot PRs after CI passes.

| Condition | Action |
|-----------|--------|
| Dependabot PR + minor/patch | Auto-merge with squash |
| GitHub Actions update | Auto-merge immediately |

### Release Drafter (`release-drafter.yaml`)

Automatically generates release notes from merged PRs.

- Groups changes by type (features, fixes, dependencies)
- Auto-labels PRs based on file paths
- Maintains a draft release

### Labeler (`labeler.yaml`)

Automatically labels PRs based on changed files.

| Path Pattern | Label |
|--------------|-------|
| `kubernetes/**` | `area/kubernetes` |
| `docs/**` | `area/docs` |
| `.github/**` | `area/ci` |
| `talos/**` | `area/talos` |
| `kubernetes/apps/monitoring/**` | `area/monitoring` |
| `kubernetes/apps/network/**` | `area/network` |

### Droid Code Review (`droid-review.yaml`)

AI-powered code review using Factory's Droid.

- Triggers on PR open/sync
- Reviews Kubernetes/Flux manifests
- Posts inline comments for issues
- Focuses on: YAML errors, security issues, misconfigurations

```yaml
# Requires FACTORY_API_KEY secret
droid exec --auto high -f prompt.txt
```

### Droid CI Fix (`droid-fix.yaml`)

Automatically fixes CI failures on feature branches.

- Triggers when Validate workflow fails
- Analyzes failure logs
- Auto-fixes common issues (syntax, validation)
- Commits and pushes the fix

```
Workflow: Validate fails → Droid analyzes → Fixes code → Pushes commit
```

## Renovate

Configured in `.github/renovate.json5` for automated dependency updates.

### What Renovate Updates

| Category | Examples |
|----------|----------|
| **Helm Charts** | kube-prometheus-stack, cert-manager, cilium |
| **Container Images** | grafana, prometheus, homepage |
| **GitHub Actions** | actions/checkout, actions/upload-artifact |
| **Flux Components** | flux-operator, flux-instance |

### Configuration Highlights

```json5
{
  "extends": ["config:recommended"],
  "flux": { "fileMatch": ["kubernetes/.+\\.ya?ml$"] },
  "helm-values": { "fileMatch": ["kubernetes/.+\\.ya?ml$"] },
  "automerge": true,
  "automergeType": "squash"
}
```

### Auto-merge Rules

- **Patch/minor updates**: Auto-merge after CI passes
- **Major updates**: Require manual review
- **Security updates**: Prioritized and auto-merged

## Pre-commit Hooks

Local development hooks configured in `.pre-commit-config.yaml`.

### Installation

```bash
pip install pre-commit
pre-commit install
```

### Hooks

| Hook | Purpose |
|------|---------|
| `trailing-whitespace` | Remove trailing spaces |
| `end-of-file-fixer` | Ensure newline at EOF |
| `check-yaml` | YAML syntax validation |
| `detect-private-key` | Block accidental key commits |
| `yamllint` | YAML style linting |
| `kubeconform` | K8s manifest validation |
| `forbid-secrets` | Ensure SOPS encryption |
| `shellcheck` | Shell script linting |
| `markdownlint` | Markdown formatting |

## Flux GitOps

The cluster uses Flux for GitOps-based deployments.

### Reconciliation Flow

1. **Push to main** → GitHub webhook notifies Flux
2. **Source Controller** → Pulls latest Git revision
3. **Kustomize Controller** → Applies Kustomizations
4. **Helm Controller** → Reconciles HelmReleases

### Webhook Configuration

Flux webhook receiver for instant sync on push:

```
URL: https://flux-webhook.ragas.cc/hook/<token>
Events: push
Content-Type: application/json
```

Get webhook path:
```bash
kubectl -n flux-system get receiver github-webhook -o jsonpath='{.status.webhookPath}'
```

## Security Scanning

### Trivy (via `security.yaml`)

- Scans Kubernetes manifests for misconfigurations
- Runs on PRs and weekly schedule
- Reports findings to GitHub Security tab

### Gitleaks

- Scans for accidentally committed secrets
- Blocks PRs with detected credentials

## Notifications

### Discord Integration

Flux sends deployment notifications to Discord.

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: discord
spec:
  type: discord
  secretRef:
    name: discord-webhook
```

Events sent:
- Kustomization reconciliation (success/failure)
- HelmRelease updates
- Deployment errors

## Best Practices

### Commit Messages

Follow conventional commits:
```
<type>(<scope>): <description>

Types: feat, fix, chore, docs, ci, refactor
Scopes: flux, helm, container, github-action
```

Examples:
```
feat(helm): add new monitoring dashboard
fix(container): update grafana to 12.3.0
ci(github-action): bump actions/checkout to v6
```

### Branch Protection

Recommended settings for `main` branch:
- Require PR reviews
- Require status checks (Validate workflow)
- Require linear history

### Testing Changes

Before pushing:
```bash
# Run pre-commit hooks
pre-commit run --all-files

# Test Flux locally
flux-local test --path kubernetes/flux

# Diff changes
flux-local diff ks -p kubernetes/flux
```
