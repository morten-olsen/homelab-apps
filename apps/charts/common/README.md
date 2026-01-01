# Common Library Chart

This is a Helm library chart that provides shared template helpers for all application charts in this repository.

## Usage

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

Then run `helm dependency update` to download the dependency.

## Available Helpers

All helpers use the `common.*` prefix:

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

## Example

In your templates, use the helpers like this:

```yaml
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
```

## Values Structure

The library expects a standardized values structure. See `audiobookshelf/values.yaml` for an example.
