# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes Helm-based homelab application deployment system using ArgoCD for GitOps. Contains 40+ containerized applications deployed via Helm charts with a shared common library to minimize template duplication.

## Commands

```bash
# Validate YAML files
yamllint .

# Helm chart operations (run from chart directory)
helm dependency build           # Fetch common library dependency
helm lint .                     # Validate chart syntax
helm template <release> . --set globals.environment=prod --set globals.domain=example.com

# Utility scripts
./scripts/migrate_database.py <source_db> <dest_db> [--clean]  # PostgreSQL migration
./scripts/sync_pvc_with_host.sh <host-path> <namespace> <pvc>  # PVC sync
```

## Architecture

### Directory Structure
- `apps/charts/` - Individual application Helm charts (deployed to `prod` namespace)
- `apps/common/` - Shared Helm library chart with standardized templates
- `apps/root/` - ArgoCD ApplicationSet for auto-discovery
- `shared/charts/` - Shared infrastructure services (authentik, nats)
- `scripts/` - Python/Bash utility scripts for database migration and PVC sync

### Deployment Model
Three ArgoCD ApplicationSets auto-discover charts from their respective `charts/` directories. Folders suffixed with `.disabled` are excluded from deployment.

### Common Library Pattern
Most charts use the common library (`apps/common/`) which provides standardized templates. A minimal chart needs:

1. `Chart.yaml` with common library dependency:
```yaml
apiVersion: v2
version: 1.0.0
name: my-app
dependencies:
  - name: common
    version: 1.0.0
    repository: file://../../common
```

2. Standardized `values.yaml` (see `apps/common/README.md` for full structure)

3. Template files that include common helpers:
```yaml
# templates/deployment.yaml
{{ include "common.deployment" . }}
```

Or use single file with `{{ include "common.all" . }}` to render all resources automatically.

### Key Templates
- `common.deployment` - Deployment with health probes, volumes, init containers
- `common.service` - Service(s) with port mapping
- `common.pvc` - Persistent volume claims
- `common.virtualService` - Istio routing (public/private gateways)
- `common.oidc` - Authentik OIDC client registration
- `common.database` - PostgreSQL database provisioning
- `common.externalSecrets` - Password generators and secret templates

### Placeholders in values.yaml
- `{release}` - Release name
- `{namespace}` - Release namespace
- `{fullname}` - Full app name
- `{subdomain}` - App subdomain (from `subdomain` value)
- `{domain}` - Global domain
- `{timezone}` - Global timezone

### Secret Naming Conventions
- OIDC credentials: `{release}-oidc-credentials` (clientId, clientSecret, issuer)
- Database connection: `{release}-connection` (url, host, port, user, password)
- Generated secrets: `{release}-secrets`

## Conventions

- Chart and release names use kebab-case
- All container images pinned by SHA256 digest (Renovate manages updates)
- Storage uses `persistent` storageClassName
- Istio VirtualServices route via public/private gateways
- Deployment strategy: `Recreate` for stateful apps, `RollingUpdate` for stateless

## YAML Style
- Max line length: 120 characters
- Indentation: 2 spaces
- Truthy values: `true`, `false`, `on`, `off`

## Documentation
- `AGENTS.md` - Chart creation guidelines
- `apps/common/README.md` - Complete common library reference
- `apps/common/MIGRATION.md` - Guide for migrating charts to common library
- `apps/common/TEMPLATING.md` - Placeholder system documentation
