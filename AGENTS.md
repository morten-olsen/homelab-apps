# Application Helm Charts Guide

This document provides guidelines for creating and maintaining Helm charts in this homelab project.

## Project Structure

```
apps/
├── charts/           # Individual application Helm charts
│   ├── app-name/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── pvc.yaml
│   │       ├── client.yaml      # OIDC client configuration
│   │       ├── database.yaml    # Database provisioning
│   │       ├── secret.yaml      # Secret generation
│   │       └── external-http-service.yaml
│   └── ...
└── root/            # ArgoCD ApplicationSet for auto-discovery
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── applicationset.yaml
        └── project.yaml

foundation/
├── charts/          # Foundation service Helm charts
│   └── ...
└── root/            # ArgoCD ApplicationSet for foundation services

shared/
├── charts/          # Shared service Helm charts
│   └── ...
└── root/            # ArgoCD ApplicationSet for shared services
```

## ArgoCD ApplicationSets

This project uses three separate ArgoCD ApplicationSets to manage different categories of services:

1. **apps/** - Individual applications (web apps, tools, services)
2. **foundation/** - Core infrastructure for the cluster (monitoring, certificates, operators)
3. **shared/** - Infrastructure shared between applications (databases, message queues, caches)

Each category has its own `root/` chart containing an ApplicationSet that auto-discovers and deploys charts from its respective `charts/` directory.

## Creating a New Application Chart

### 1. Basic Chart Structure

Create a new directory under `apps/charts/` with the following structure:

```bash
mkdir -p apps/charts/my-app/templates
```

#### Chart.yaml

```yaml
apiVersion: v2
version: 1.0.0
name: my-app
```

#### values.yaml

```yaml
image:
  repository: docker.io/org/my-app
  tag: v1.0.0
  pullPolicy: IfNotPresent
subdomain: my-app
```

See ./apps/common/README.md for guide on writing charts

