# Deploying a New Service

This guide walks through deploying a new service to the Kubernetes cluster using GitOps.

## Prerequisites

- Git repository access
- kubectl configured with cluster access
- Basic understanding of Kubernetes resources

## Step 1: Create the App Directory Structure

```bash
mkdir -p kubernetes/apps/<namespace>/<app-name>/app
```

Example for deploying `my-app` in the `default` namespace:
```bash
mkdir -p kubernetes/apps/default/my-app/app
```

## Step 2: Create the HelmRelease (or Deployment)

### Option A: Using a Helm Chart

Create `kubernetes/apps/default/my-app/app/helmrelease.yaml`:

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: my-app
spec:
  interval: 30m
  chart:
    spec:
      chart: my-app
      version: 1.0.0
      sourceRef:
        kind: HelmRepository
        name: my-repo
        namespace: flux-system
  values:
    # Your Helm values here
    replicaCount: 2
    image:
      repository: my-app
      tag: latest
```

### Option B: Using Raw Manifests

Create `kubernetes/apps/default/my-app/app/deployment.yaml`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

## Step 3: Create the HTTPRoute (Ingress)

Create `kubernetes/apps/default/my-app/app/httproute.yaml`:

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
  hostnames:
    - "my-app.ragas.cc"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app
          port: 80
```

## Step 4: Create the Kustomization

Create `kubernetes/apps/default/my-app/app/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml  # or deployment.yaml
  - httproute.yaml
```

## Step 5: Create the Flux Kustomization

Create `kubernetes/apps/default/my-app/ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  targetNamespace: default
  commonMetadata:
    labels:
      app.kubernetes.io/name: my-app
  path: ./kubernetes/apps/default/my-app/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: true
  interval: 30m
  timeout: 5m
```

## Step 6: Update Parent Kustomization

Edit `kubernetes/apps/default/kustomization.yaml` to include your app:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - echo/ks.yaml
  - homepage/ks.yaml
  - my-app/ks.yaml  # Add this line
```

## Step 7: Commit and Push

```bash
git add kubernetes/apps/default/my-app
git commit -m "feat(apps): add my-app deployment"
git push
```

## Step 8: Monitor Deployment

```bash
# Watch Flux reconciliation
flux get ks -A --watch

# Check HelmRelease status
flux get hr -A

# Check pods
kubectl get pods -n default -l app=my-app

# Check HTTPRoute
kubectl get httproute -A
```

## Step 9: Verify Access

1. Ensure DNS is configured (AdGuard should forward `ragas.cc` to `k8s-gateway` at `172.16.1.60`)
2. Access https://my-app.ragas.cc
3. Check certificate status:
   ```bash
   kubectl get certificates -A
   ```

## Troubleshooting

### App not deploying
```bash
# Check Flux logs
flux logs --kind=Kustomization --name=my-app

# Check HelmRelease status
kubectl describe hr my-app -n default
```

### HTTPRoute not working
```bash
# Check gateway status
kubectl get gateway -n network

# Check route status
kubectl describe httproute my-app -n default

# Check Envoy logs
kubectl logs -n network -l app.kubernetes.io/name=envoy
```

### Certificate issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate status
kubectl describe certificate -n network
```

## Best Practices

1. **Use HelmRelease** for complex apps with many config options
2. **Pin versions** - never use `latest` in production
3. **Add health checks** to your deployments
4. **Set resource requests**; add limits only when needed
5. **Enable PodDisruptionBudgets** for HA apps
6. **Use SOPS** for secrets, never commit plain secrets

## Example: Complete App Structure

```
kubernetes/apps/default/my-app/
├── app/
│   ├── helmrelease.yaml
│   ├── httproute.yaml
│   ├── kustomization.yaml
│   └── secret.sops.yaml  # Encrypted secrets
└── ks.yaml
```
