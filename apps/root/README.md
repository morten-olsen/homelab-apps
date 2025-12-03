# ArgoCD Apps

This Helm chart deploys an ArgoCD ApplicationSet and AppProject to manage homelab applications.

## Description

It sets up:
-   **AppProject**: A project named `apps` (configurable) to group the applications.
-   **ApplicationSet**: Automatically discovers and deploys Helm charts from `charts/apps/*` in the repository.

## Prerequisites

-   Kubernetes cluster
-   ArgoCD installed in the `argocd` namespace

## Deployment

### Option 1: Helm Install

Run the following command to install the chart directly:

```bash
helm upgrade --install argocd-apps ./apps/root \
  --namespace argocd
```

### Option 2: ArgoCD App of Apps

You can also deploy this chart using ArgoCD itself by creating an Application that points to this chart.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/morten-olsen/homelab-apps
    targetRevision: main
    path: charts/argocd-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repoURL` | URL of the git repository | `https://github.com/morten-olsen/homelab-apps` |
| `targetRevision` | Git revision to use | `main` |
| `path` | Path to the apps directory | `charts/apps` |
| `exclude` | Pattern to exclude directories | `*.disabled` |
| `project` | ArgoCD project name | `apps` |
