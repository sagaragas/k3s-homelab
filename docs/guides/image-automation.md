# Flux Image Automation

This guide explains how container images are automatically updated in the cluster.

## Overview

Flux Image Automation automatically:

1. **Scans** container registries for new tags
2. **Evaluates** tags against version policies
3. **Updates** image references in Git
4. **Commits** and pushes changes
5. **Deploys** via normal GitOps flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Image Registry  │────►│ Image Reflector │────►│  Image Policy   │
│  (Docker Hub,   │     │   Controller    │     │   (semver)      │
│   GHCR, etc.)   │     └─────────────────┘     └────────┬────────┘
└─────────────────┘                                      │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Cluster      │◄────│   Flux GitOps   │◄────│ Image Update    │
│   Deployment    │     │                 │     │  Automation     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Components

### Image Reflector Controller

Scans container registries and stores available tags.

```bash
# Check controller status
kubectl get deployment -n flux-system image-reflector-controller
```

### Image Automation Controller

Commits image updates back to Git.

```bash
# Check controller status
kubectl get deployment -n flux-system image-automation-controller
```

## Configuration

### ImageRepository

Defines which container registry to scan.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: homepage
  namespace: flux-system
spec:
  image: ghcr.io/gethomepage/homepage
  interval: 6h
  exclusionList:
    - "^.*-dev$"  # Exclude dev tags
```

**Current repositories:**

| Name | Image | Scan Interval |
|------|-------|---------------|
| homepage | `ghcr.io/gethomepage/homepage` | 6h |
| mkdocs-material | `squidfunk/mkdocs-material` | 6h |
| grafana | `grafana/grafana` | 6h |

Check status:
```bash
kubectl get imagerepository -n flux-system
```

### ImagePolicy

Defines version selection rules.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: homepage
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: homepage
  policy:
    semver:
      range: ">=0.9.0"  # Any version >= 0.9.0
```

**Policy types:**

| Type | Example | Use Case |
|------|---------|----------|
| `semver.range` | `>=1.0.0` | Follow semantic versioning |
| `semver.range` | `1.x` | Stay on major version 1 |
| `numerical` | `asc` or `desc` | Numeric tags |
| `alphabetical` | `asc` or `desc` | Alphabetic tags |

**Current policies:**

| Image | Policy | Latest Tag |
|-------|--------|------------|
| homepage | `>=0.9.0` | v1.7.0 |
| mkdocs-material | `9.x` | 9.7.0 |
| grafana | `>=11.0.0` | 12.3.0 |

Check status:
```bash
kubectl get imagepolicy -n flux-system
```

### ImageUpdateAutomation

Configures how updates are committed.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 30m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        name: flux-image-automation
        email: flux@ragas.cc
      messageTemplate: |
        chore(container): update images
        
        Automated image update
    push:
      branch: main
  update:
    path: ./kubernetes
    strategy: Setters
```

Check status:
```bash
kubectl get imageupdateautomation -n flux-system
kubectl describe imageupdateautomation flux-system -n flux-system
```

## Adding a New Image

### Step 1: Create ImageRepository

```yaml
# kubernetes/apps/flux-system/image-automation/app/image-repositories.yaml
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: my-app
spec:
  image: docker.io/myorg/my-app
  interval: 6h
```

### Step 2: Create ImagePolicy

```yaml
# kubernetes/apps/flux-system/image-automation/app/image-policies.yaml
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: my-app
spec:
  imageRepositoryRef:
    name: my-app
  policy:
    semver:
      range: ">=1.0.0"
```

### Step 3: Add Image Marker

Add a comment marker to your deployment:

```yaml
# In your deployment.yaml
containers:
  - name: my-app
    image: docker.io/myorg/my-app:1.0.0 # {"$imagepolicy": "flux-system:my-app"}
```

The marker format is:
```
# {"$imagepolicy": "<namespace>:<policy-name>"}
```

### Step 4: Commit and Push

```bash
git add -A
git commit -m "feat: add image automation for my-app"
git push
```

## Troubleshooting

### Image not updating

1. **Check ImageRepository status:**
   ```bash
   kubectl describe imagerepository <name> -n flux-system
   ```
   Look for scan errors or authentication issues.

2. **Check ImagePolicy status:**
   ```bash
   kubectl describe imagepolicy <name> -n flux-system
   ```
   Verify the policy matches available tags.

3. **Check ImageUpdateAutomation:**
   ```bash
   kubectl describe imageupdateautomation flux-system -n flux-system
   ```
   Look for Git push errors.

### Private registry authentication

For private registries, create a secret:

```bash
kubectl create secret docker-registry regcred \
  --namespace flux-system \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token>
```

Reference in ImageRepository:
```yaml
spec:
  secretRef:
    name: regcred
```

### Force immediate scan

```bash
flux reconcile image repository <name>
```

### View all image updates

```bash
# See what images would be updated
kubectl get imagepolicy -n flux-system -o wide

# See last update time
kubectl get imageupdateautomation -n flux-system
```

## Best Practices

### 1. Use Semver Ranges

Prefer semantic versioning to avoid breaking changes:
```yaml
# Good - stay on major version
range: "1.x"

# Good - minimum version
range: ">=1.0.0 <2.0.0"

# Risky - any version
range: "*"
```

### 2. Exclude Pre-release Tags

```yaml
spec:
  exclusionList:
    - "^.*-alpha.*$"
    - "^.*-beta.*$"
    - "^.*-rc.*$"
    - "^.*-dev$"
```

### 3. Set Appropriate Scan Intervals

| Image Type | Recommended Interval |
|------------|---------------------|
| Critical (CNI, DNS) | 12h-24h |
| Applications | 6h |
| Development | 1h |

### 4. Monitor Automated Commits

Watch for image update commits:
```bash
git log --oneline --author="flux-image-automation"
```

## Files Reference

```
kubernetes/apps/flux-system/image-automation/
├── app/
│   ├── image-repositories.yaml  # Registry definitions
│   ├── image-policies.yaml      # Version policies
│   ├── image-update-automation.yaml  # Git commit config
│   └── kustomization.yaml
└── ks.yaml  # Flux Kustomization
```
