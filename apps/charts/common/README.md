# Common Library Chart

This is a Helm library chart that provides shared template helpers for all application charts in this repository.

## Quick Start

To use this library chart in your application chart, add it as a dependency in your `Chart.yaml`:

```yaml
apiVersion: v2
version: 1.0.0
name: your-app
dependencies:
  - name: common
    version: 1.0.0
    repository: file://../common
```

Then run `helm dependency build` to download the dependency.

## Documentation

- **[MIGRATION.md](./MIGRATION.md)** - Complete guide for migrating existing charts
- **[TEMPLATING.md](./TEMPLATING.md)** - Guide to using placeholders in values.yaml

## Available Templates

The library provides full resource templates that can be included directly:

- `common.deployment` - Full Deployment resource
- `common.service` - Full Service resource(s) - supports multiple services
- `common.pvc` - Full PVC resources - supports multiple PVCs
- `common.virtualService` - Full VirtualService resources (public + private)
- `common.dns` - Full DNSRecord resource
- `common.oidc` - Full AuthentikClient resource
- `common.database` - Full PostgresDatabase resource
- `common.externalSecrets` - Full ExternalSecret resources with Password generators

## Usage Example

Replace your template files with simple includes:

```yaml
# deployment.yaml
{{ include "common.deployment" . }}

# service.yaml
{{ include "common.service" . }}

# pvc.yaml
{{ include "common.pvc" . }}
```

## Available Helpers

Helper functions for custom templates:

- `common.fullname` - Full name of the release
- `common.name` - Name of the chart
- `common.labels` - Standard Kubernetes labels
- `common.selectorLabels` - Selector labels for matching
- `common.deploymentStrategy` - Deployment strategy (defaults to Recreate)
- `common.containerPort` - Container port (defaults to 80)
- `common.servicePort` - Service port (defaults to 80)
- `common.healthProbe` - Health probe configuration
- `common.domain` - Full domain name (subdomain.domain)
- `common.url` - Full URL (https://subdomain.domain)
- `common.volumeMounts` - Volume mounts from values
- `common.volumes` - Volumes from values
- `common.env` - Environment variables including TZ
- `common.virtualServiceGatewaysPublic` - Public gateway list
- `common.virtualServiceGatewaysPrivate` - Private gateway list

## Values Structure

The library expects a standardized values structure. See migrated charts (`audiobookshelf`, `forgejo`, `baikal`, `blinko`) for examples.

## Placeholders

Use placeholders in `values.yaml` for dynamic values:

- `{release}` - Release name
- `{namespace}` - Release namespace
- `{fullname}` - Full app name
- `{subdomain}` - Application subdomain
- `{domain}` - Global domain
- `{timezone}` - Global timezone

See [TEMPLATING.md](./TEMPLATING.md) for complete documentation.
