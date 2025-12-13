---
name: deploy-app
description: Deploy a new application to the Kubernetes cluster using GitOps patterns
---

# Deploy Application Skill

Deploy a new application to the k3s homelab cluster following GitOps best practices.

## When to Use
- User wants to add a new application to the cluster
- User wants to deploy a Helm chart
- User asks about deploying services

## Process

1. **Create app directory structure:**
   ```
   kubernetes/apps/<namespace>/<app-name>/
   ├── app/
   │   ├── helmrelease.yaml
   │   └── kustomization.yaml
   └── ks.yaml
   ```

2. **Create HelmRelease** (`app/helmrelease.yaml`):
   ```yaml
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: <app-name>
   spec:
     chartRef:
       kind: OCIRepository  # or HelmRepository
       name: <chart-name>
       namespace: <namespace>
     interval: 1h
     values:
       # App-specific values
   ```

3. **Create Kustomization** (`app/kustomization.yaml`):
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - helmrelease.yaml
   ```

4. **Create Flux Kustomization** (`ks.yaml`):
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: <app-name>
   spec:
     interval: 1h
     path: ./kubernetes/apps/<namespace>/<app-name>/app
     prune: true
     sourceRef:
       kind: GitRepository
       name: flux-system
       namespace: flux-system
     targetNamespace: <namespace>
     wait: false
     healthChecks:
       - apiVersion: apps/v1
         kind: Deployment
         name: <app-name>
         namespace: <namespace>
   ```

5. **Register in parent namespace ks.yaml**

6. **Add ingress if needed** (HTTPRoute for Envoy Gateway)

## Variables to Collect
- App name
- Namespace (default, media, home, monitoring, etc.)
- Helm chart source (OCI registry or Helm repository)
- Chart version
- Custom values
- Whether external ingress is needed
