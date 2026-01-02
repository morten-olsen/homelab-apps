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
    repository: file://../../common
```

### Step 2: Restructure values.yaml

Convert your existing `values.yaml` to the standardized format:

#### Before (Old Format)

```yaml
image:
  repository: docker.io/org/app
  tag: latest
subdomain: myapp
```

#### After (Standardized Format)

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

# OIDC client configuration (if applicable)
oidc:
  enabled: true
  redirectUris:
    - "/api/auth/callback/authentik"
  subjectMode: user_username  # Optional, defaults to "user_username"

# Database configuration (if applicable)
database:
  enabled: true

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

#### database.yaml (if applicable)

**Before:** ~10 lines  
**After:**

```yaml
{{ include "common.database" . }}
```

#### secret.yaml (if using External Secrets)

**Before:** ~10 lines (GenerateSecret)  
**After (recommended - split files for correct ordering):**

Create two files:

`templates/secret-password-generators.yaml`:

```yaml
{{ include "common.externalSecrets.passwordGenerators" . }}
```

`templates/secret-external-secrets.yaml`:

```yaml
{{ include "common.externalSecrets.externalSecrets" . }}
```

**Alternative (single file):**

```yaml
{{ include "common.externalSecrets" . }}
```

**Note:** Splitting into separate files ensures Password generators are created before ExternalSecrets, which prevents sync errors.

### Step 4: Update Dependencies

Build the chart dependencies:

```bash
cd apps/charts/your-app
helm dependency build
```

**Note:** The common library is located at `apps/common/`, so charts in `apps/charts/` use `repository: file://../../common`.

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

### External Secrets (Password Generation)

```yaml
# External Secrets configuration
externalSecrets:
  - name: "{release}-secrets"  # Secret name (supports placeholders)
    passwords:
      - name: betterauth        # Generator name (used in generator resource name)
        length: 64               # Password length (default: 32)
        allowRepeat: true        # Allow repeated characters (default: false)
                                 # Required for passwords longer than ~50 characters
        noUpper: false           # Disable uppercase (default: false)
        encoding: hex            # Encoding format: raw (default), hex, base64, base64url, base32
        secretKeys:              # Required: sets the key name in the secret
          - betterauth           # Without this, the key defaults to "password"
      - name: apitoken           # Generator name
        length: 32
        allowRepeat: false       # Can be false for shorter passwords
        secretKeys:              # Required: sets the key name in the secret
          - apitoken             # Without this, the key defaults to "password"
```

**Important:** For passwords longer than approximately 50 characters, you must set `allowRepeat: true`. The default character set (uppercase, lowercase, digits) doesn't have enough unique characters to generate very long passwords without repeats.

**Multiple secrets:**

```yaml
externalSecrets:
  - name: "{release}-secrets"
    passwords:
      - name: password
        length: 32
  - name: "{release}-api-keys"
    passwords:
      - name: apikey
        length: 64
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

## Database Configuration

The common library supports the new PostgreSQL database resource (API version `postgres.homelab.mortenolsen.pro/v1`).

### Enabling Database Support

Add to your `values.yaml`:

```yaml
# Database configuration
database:
  enabled: true
```

### Database Template

Create `templates/database.yaml`:

```yaml
{{ include "common.database" . }}
```

### Generated Secret

The PostgresDatabase resource creates a secret named `{release}-connection` containing:

- `url` - Complete PostgreSQL connection URL
- `host` - Database hostname
- `port` - Database port
- `database` - Database name
- `username` - Database username
- `password` - Database password

### Using Database Secrets

Reference the database secret in your environment variables:

```yaml
env:
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "{release}-connection"
        key: url
  DB_HOST:
    valueFrom:
      secretKeyRef:
        name: "{release}-connection"
        key: host
```

### Global Configuration

The database resource requires global configuration in `apps/root/values.yaml`:

```yaml
globals:
  database:
    ref:
      name: postgres
      namespace: shared
```

### Migration from Legacy PostgresDatabase

If migrating from the legacy `homelab.mortenolsen.pro/v1` PostgresDatabase:

1. **Update API version**: Changed from `homelab.mortenolsen.pro/v1` to `postgres.homelab.mortenolsen.pro/v1`
2. **Update spec**: Changed from `environment` to `clusterRef` with `name` and `namespace`
3. **Update secret name**: Changed from `{release}-pg-connection` to `{release}-connection`
4. **Add namespace**: Metadata now includes `namespace: {{ .Release.Namespace }}`

The common library template handles all of this automatically.

### Migrating Database from Old Server to New Server

When migrating databases from the old PostgreSQL server (`prod-postgres-cluster-0` in `homelab` namespace) to the new server (`postgres-statefulset-0` in `shared` namespace), use the migration script.

#### Database Naming Convention

Database names follow the pattern `{namespace}_{name}` where:

- `{namespace}` is the Kubernetes namespace (default: `prod`)
- `{name}` is the application name (release name)

**Examples:**

- `prod_blinko` - blinko app in prod namespace
- `prod_gitea` - gitea app in prod namespace
- `shared_authentik-db` - authentik app in shared namespace

#### Using the Migration Script

The migration script is located at `scripts/migrate_database.py` and handles:

- Dumping the database from the old server
- Restoring to the new server
- Fixing permissions and ownership automatically

The script can not be used until the new database is deployed, so it shouldn't be used as part of the migration

**Basic Usage:**

```bash
./scripts/migrate_database.py <source_db_name> <dest_db_name>
```

**Example:**

```bash
# Migrate prod_blinko database (same name on both servers)
./scripts/migrate_database.py prod_blinko prod_blinko
```

**With Different Database Names:**

```bash
# Migrate from old_name to new_name
./scripts/migrate_database.py old_name new_name
```

**With Custom PostgreSQL Users:**

```bash
# If the PostgreSQL users differ from defaults
./scripts/migrate_database.py prod_blinko prod_blinko \
  --source-user homelab \
  --dest-user postgres
```

**Overwriting Existing Data:**

```bash
# Use --clean flag to drop existing objects before restoring
# WARNING: This will DELETE all existing data in the destination database!
./scripts/migrate_database.py prod_blinko prod_blinko --clean
```

#### Behavior with Existing Databases

**Without `--clean` flag:**

- The script will attempt to restore objects to the destination database
- If tables/objects already exist, `pg_restore` may:
  - Fail with errors (e.g., "relation already exists")
  - Cause data conflicts (duplicate key violations)
  - Partially restore data
- **This will NOT automatically overwrite existing data**

**With `--clean` flag:**

- Drops all existing objects (tables, sequences, functions, etc.) before restoring
- **WARNING: This will DELETE all existing data in the destination database**
- Use this when you want to completely replace the destination database with source data
- Recommended for initial migrations or when you're sure you want to overwrite

**Best Practice:**

- For initial migrations: Use `--clean` to ensure a clean restore
- For updates/re-syncs: Use `--clean` only if you're certain you want to replace all data
- For incremental updates: Consider using application-specific sync mechanisms instead

#### Prerequisites

1. **Destination database must exist** - The script will verify but not create the database
2. **Both pods must be running** - The script checks this automatically
3. **Source database must exist** - The script verifies this before starting

#### What the Script Does

1. Verifies both PostgreSQL pods are running
2. Checks that source and destination databases exist
3. Dumps the source database using `pg_dump` (custom format)
4. Restores to the destination database using `pg_restore`
5. Automatically fixes permissions:
   - Grants USAGE and CREATE on all schemas to the database user
   - Changes schema ownership to the database user
   - Grants ALL privileges on all tables and sequences
   - Sets default privileges for future objects

#### Default Configuration

The script uses these defaults:

- **Source server**: `prod-postgres-cluster-0` in `homelab` namespace
- **Source user**: `homelab`
- **Destination server**: `postgres-statefulset-0` in `shared` namespace
- **Destination user**: `postgres`

#### Troubleshooting

**Error: "role does not exist"**

- Check the PostgreSQL user name with: `kubectl exec -n <namespace> <pod> -c <container> -- env | grep POSTGRES_USER`
- Use `--source-user` or `--dest-user` flags to specify correct users

**Error: "database does not exist"**

- Create the destination database manually before running the script
- Verify database names match the `{namespace}_{name}` convention

**Error: "permission denied for schema"**

- The script should fix this automatically
- If issues persist, manually grant permissions:

  ```sql
  GRANT USAGE ON SCHEMA <schema_name> TO <db_user>;
  GRANT CREATE ON SCHEMA <schema_name> TO <db_user>;
  ALTER SCHEMA <schema_name> OWNER TO <db_user>;
  ```

## Handling Legacy Resources

Some charts may still have legacy resources that should be kept as-is:

- **OidcClient** (legacy `homelab.mortenolsen.pro/v1`) - Use `common.oidc` for new AuthentikClient instead
- **PostgresDatabase** (legacy `homelab.mortenolsen.pro/v1`) - Use `common.database` for new PostgresDatabase instead
- **GenerateSecret** (legacy `homelab.mortenolsen.pro/v1`) - Use `common.externalSecrets` for External Secrets instead

### Migrating from OidcClient to AuthentikClient

**Before (OidcClient):**

```yaml
# templates/client.yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: OidcClient
metadata:
  name: "{{ .Release.Name }}"
spec:
  environment: "{{ .Values.globals.environment }}"
  redirectUris:
    - path: oauth2/oidc/callback
      subdomain: "{{ .Values.subdomain }}"
      matchingMode: strict
```

**After (AuthentikClient):**

```yaml
# values.yaml
oidc:
  enabled: true
  redirectUris:
    - "/oauth2/oidc/callback"  # Path only, domain is automatically prepended
  subjectMode: user_username  # Optional, defaults to "user_username"

# templates/client.yaml (or oidc.yaml)
{{ include "common.oidc" . }}
```

**Key Changes:**

1. **API Version**: Changed from `homelab.mortenolsen.pro/v1` to `authentik.homelab.mortenolsen.pro/v1alpha1`
2. **Resource Kind**: Changed from `OidcClient` to `AuthentikClient`
3. **Redirect URIs**: Now specified as paths only (e.g., `"/oauth2/oidc/callback"`). The full URL is automatically constructed as `https://{subdomain}.{domain}{path}`
4. **Subject Mode**: New `subjectMode` field defaults to `"user_username"` but can be customized
5. **Secret Name**: The generated secret name changed from `{release}-client` to `{release}-oidc-credentials`
6. **Secret Keys**: The secret key `configurationIssuer` changed to `issuer`

**Environment Variable Updates:**

When migrating, update your environment variables to reference the new secret:

```yaml
env:
  OAUTH2_CLIENT_ID:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"  # Changed from {release}-client
        key: clientId
  OAUTH2_CLIENT_SECRET:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"  # Changed from {release}-client
        key: clientSecret
  OAUTH2_OIDC_DISCOVERY_ENDPOINT:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"  # Changed from {release}-client
        key: issuer  # Changed from configurationIssuer
```

**Subject Mode Options:**

The `subjectMode` field controls how the subject identifier is generated:
- `user_username` (default) - Uses the username as the subject identifier
- `user_email` - Uses the email address as the subject identifier
- `user_id` - Uses the user ID as the subject identifier

### Migrating from GenerateSecret to External Secrets

**Before (GenerateSecret):**

```yaml
# templates/secret.yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: GenerateSecret
metadata:
  name: '{{ .Release.Name }}-secrets'
spec:
  fields:
    - name: betterauth
      encoding: base64
      length: 64
```

**After (External Secrets):**

```yaml
# values.yaml
externalSecrets:
  - name: "{release}-secrets"
    passwords:
      - name: betterauth
        length: 64
        allowRepeat: true  # Required for passwords >50 chars
        noUpper: false
        encoding: hex      # hex, base64, base64url, base32, or raw (default)
        secretKeys:
          - betterauth  # Required: sets the key name in the secret

# templates/secret.yaml
{{ include "common.externalSecrets" . }}
```

**Note:**

- External Secrets generates passwords directly (no encoding option)
- The `secretKeys` field is **required** to set the key name in the secret
- Without `secretKeys`, the Password generator defaults to using `password` as the key name
- The `name` field in the password config is used for the generator name, not the secret key name

## Troubleshooting

### Issue: Dependency Not Found

**Error:** `found in Chart.yaml, but missing in charts/ directory: common`

**Solution:**

```bash
cd apps/charts/your-app
rm -rf charts Chart.lock
helm dependency build
```

**Note:** After changing the repository path in `Chart.yaml` (e.g., from `file://../common` to `file://../../common`), you must delete `Chart.lock` and rebuild dependencies.

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
- [ ] Database resource created (if applicable)
- [ ] Database secret references use correct name (`{release}-connection`)
- [ ] External Secrets created (if applicable)
- [ ] Password generators created for each secret field

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
