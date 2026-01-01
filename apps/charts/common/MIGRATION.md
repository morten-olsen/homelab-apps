# Migration Guide: Converting Charts to Use Common Library

This guide explains how to migrate existing Helm charts to use the common library chart, significantly reducing code duplication and standardizing patterns across all charts.

## Overview

Migrating a chart to use the common library involves:
1. Adding the common library as a dependency
2. Restructuring `values.yaml` to match the standardized format
3. Replacing template files with simple includes
4. Testing the migrated chart

## Benefits

- **96% code reduction**: Templates go from ~150-200 lines to ~6 lines
- **Single source of truth**: Bug fixes and improvements benefit all charts
- **Consistency**: All charts follow the same patterns
- **Easier maintenance**: Less code to review and maintain

## Step-by-Step Migration

### Step 1: Add Common Library Dependency

Update `Chart.yaml` to include the common library:

```yaml
apiVersion: v2
version: 1.0.0
name: your-app
dependencies:
  - name: common
    version: 1.0.0
    repository: file://../common
```

### Step 2: Restructure values.yaml

Convert your existing `values.yaml` to the standardized format:

#### Before (Old Format):
```yaml
image:
  repository: docker.io/org/app
  tag: latest
subdomain: myapp
```

#### After (Standardized Format):
```yaml
image:
  repository: docker.io/org/app
  tag: latest
  pullPolicy: IfNotPresent

subdomain: myapp

# Deployment configuration
deployment:
  strategy: Recreate  # or RollingUpdate
  replicas: 1
  revisionHistoryLimit: 0

# Container configuration
container:
  port: 80  # or use ports: array for multiple ports
  healthProbe:
    type: httpGet  # or tcpSocket
    path: /ping  # for httpGet

# Service configuration
service:
  port: 80
  type: ClusterIP

# Volume configuration
volumes:
  - name: data
    mountPath: /data
    persistentVolumeClaim: data  # Will be prefixed with release name

# Persistent volume claims
persistentVolumeClaims:
  - name: data
    size: 1Gi

# VirtualService configuration
virtualService:
  enabled: true
  gateways:
    public: true
    private: true

# Environment variables
env:
  MY_VAR: "value"
  URL:
    value: "https://{subdomain}.{domain}"  # Use placeholders
  SECRET:
    valueFrom:
      secretKeyRef:
        name: "{release}-secrets"
        key: apiKey
```

### Step 3: Replace Template Files

Replace your template files with simple includes:

#### deployment.yaml
**Before:** ~50-100 lines of template code  
**After:**
```yaml
{{ include "common.deployment" . }}
```

#### service.yaml
**Before:** ~15-20 lines  
**After:**
```yaml
{{ include "common.service" . }}
```

#### pvc.yaml
**Before:** ~20-30 lines per PVC  
**After:**
```yaml
{{ include "common.pvc" . }}
```

#### virtual-service.yaml
**Before:** ~40-50 lines  
**After:**
```yaml
{{ include "common.virtualService" . }}
```

#### dns.yaml (if applicable)
**Before:** ~20 lines  
**After:**
```yaml
{{ include "common.dns" . }}
```

#### oidc.yaml (if applicable)
**Before:** ~20 lines  
**After:**
```yaml
{{ include "common.oidc" . }}
```

### Step 4: Update Dependencies

Build the chart dependencies:

```bash
cd apps/charts/your-app
helm dependency build
```

### Step 5: Test the Migration

Test that the chart renders correctly:

```bash
helm template your-app apps/charts/your-app \
  --set globals.environment=prod \
  --set globals.domain=olsen.cloud \
  --set globals.timezone=Europe/Amsterdam \
  --set globals.istio.gateways.public=shared/public \
  --set globals.istio.gateways.private=shared/private \
  --set globals.authentik.ref.name=authentik \
  --set globals.authentik.ref.namespace=shared \
  --set globals.networking.private.ip=192.168.20.180
```

Verify:
- All resources render correctly
- Environment variables use placeholders correctly
- Ports and volumes are configured properly
- Health probes work as expected

## Common Patterns

### Single Port Application

```yaml
# values.yaml
container:
  port: 80
  healthProbe:
    type: httpGet
    path: /ping

service:
  port: 80
```

### Multiple Ports Application

```yaml
# values.yaml
container:
  ports:
    - name: http
      port: 3000
      protocol: TCP
    - name: ssh
      port: 22
      protocol: TCP
  healthProbe:
    type: tcpSocket
    port: http  # Use named port

service:
  ports:
    - name: http
      port: 80
      targetPort: 3000
      type: ClusterIP
    - name: ssh
      port: 2206
      targetPort: 22
      type: LoadBalancer
      serviceName: ssh  # Results in: {release}-ssh
```

### Environment Variables with Placeholders

```yaml
env:
  # Simple value
  NODE_ENV: "production"
  
  # Value with placeholders
  BASE_URL:
    value: "https://{subdomain}.{domain}"
  
  # Secret reference with placeholder
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "{release}-database"
        key: url
  
  # Multiple placeholders
  SSH_DOMAIN:
    value: "ssh-{subdomain}.{domain}"
```

### Multiple PVCs

```yaml
volumes:
  - name: data
    mountPath: /data
    persistentVolumeClaim: data
  - name: config
    mountPath: /config
    persistentVolumeClaim: config

persistentVolumeClaims:
  - name: data
    size: 10Gi
  - name: config
    size: 1Gi
```

### External PVCs (Shared Volumes)

```yaml
volumes:
  - name: shared-books
    mountPath: /books
    persistentVolumeClaim: books  # Uses PVC name as-is (not prefixed)
```

## Available Placeholders

See [TEMPLATING.md](./TEMPLATING.md) for complete placeholder documentation.

| Placeholder | Maps To | Example |
|------------|---------|---------|
| `{release}` | `.Release.Name` | `blinko`, `audiobookshelf` |
| `{namespace}` | `.Release.Namespace` | `prod`, `default` |
| `{fullname}` | `common.fullname` helper | `blinko`, `test-release-blinko` |
| `{subdomain}` | `.Values.subdomain` | `blinko`, `code` |
| `{domain}` | `.Values.globals.domain` | `olsen.cloud` |
| `{timezone}` | `.Values.globals.timezone` | `Europe/Amsterdam` |

## Migration Examples

### Example 1: Simple Application (audiobookshelf)

**Before:**
- 6 template files with ~169 total lines
- Custom health probe configuration
- Multiple PVCs

**After:**
- 6 template files with 6 total lines (one include each)
- Standardized health probe using `/ping` endpoint
- Same functionality, 96% less code

### Example 2: Multi-Port Application (forgejo)

**Before:**
- Multiple services (HTTP + SSH)
- Complex port configuration
- Multiple container ports

**After:**
- Uses `container.ports` array
- Uses `service.ports` array
- Each service can have different type (ClusterIP vs LoadBalancer)

### Example 3: Application with Database (blinko)

**Before:**
- Environment variables with template syntax
- Secret references
- Database connection strings

**After:**
- Environment variables use placeholders
- Secret references use `{release}` placeholder
- Cleaner, more maintainable values.yaml

## Handling Legacy Resources

Some charts have legacy resources that should be kept as-is:

- **OidcClient** (legacy) - Keep existing `client.yaml` template
- **PostgresDatabase** (legacy) - Keep existing `database.yaml` template
- **GenerateSecret** - Keep existing `secret.yaml` template

These will be migrated separately when the common library adds support for them.

## Troubleshooting

### Issue: Dependency Not Found

**Error:** `found in Chart.yaml, but missing in charts/ directory: common`

**Solution:**
```bash
cd apps/charts/your-app
rm -rf charts
helm dependency build
```

### Issue: Template Syntax Errors

**Error:** Template rendering fails with syntax errors

**Solution:**
- Ensure all placeholders use curly braces: `{release}`, not `{{release}}`
- Check that values.yaml uses proper YAML structure
- Verify globals are provided when testing

### Issue: Environment Variables Not Replaced

**Problem:** Placeholders like `{subdomain}` appear literally in output

**Solution:**
- Ensure you're using the latest common library version
- Rebuild dependencies: `helm dependency build`
- Check that placeholders are in `env:` section, not elsewhere

### Issue: Health Probe Not Working

**Problem:** Health probe uses wrong port or type

**Solution:**
- For named ports, use: `port: http` (the port name)
- For numeric ports, use: `port: 80` (the port number)
- Ensure `container.healthProbe.type` is set correctly

### Issue: Multiple Services Not Created

**Problem:** Only one service is created when multiple are expected

**Solution:**
- Use `service.ports` array (not `service.port`)
- Each port entry creates a separate service
- Use `serviceName` in port config for custom names

## Testing Checklist

After migration, verify:

- [ ] Chart renders without errors
- [ ] All resources are created (Deployment, Service, PVCs, etc.)
- [ ] Environment variables are correctly templated
- [ ] Secret references use correct names
- [ ] Health probes are configured correctly
- [ ] Ports match expected values
- [ ] Volumes mount correctly
- [ ] VirtualServices route to correct service
- [ ] DNS record created (if applicable)
- [ ] OIDC client created (if applicable)

## Post-Migration

After successful migration:

1. **Remove old template code** - Templates are now just includes
2. **Update documentation** - Document any app-specific requirements
3. **Test in cluster** - Deploy and verify functionality
4. **Commit changes** - Include Chart.lock in git (dependencies are tracked)

## Next Steps

Once migrated, you can:

- **Add features easily** - New environment variables, volumes, etc.
- **Update patterns** - Changes to common library benefit all charts
- **Maintain consistency** - All charts follow same patterns
- **Reduce bugs** - Single source of truth means fewer places for bugs

## Need Help?

- Check [TEMPLATING.md](./TEMPLATING.md) for placeholder documentation
- Review migrated charts: `audiobookshelf`, `forgejo`, `baikal`, `blinko`
- Test with `helm template --debug` to see rendered output
