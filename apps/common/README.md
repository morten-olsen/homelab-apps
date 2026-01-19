# Common Library Chart

This is a Helm library chart that provides shared template helpers for all application charts in this repository. It dramatically reduces code duplication by providing standardized templates for common Kubernetes resources.

## Quick Start

### 1. Create Your Chart Structure

```bash
mkdir -p apps/charts/my-app/templates
```

### 2. Add Common Library Dependency

Create `Chart.yaml`:

```yaml
apiVersion: v2
version: 1.0.0
name: my-app
dependencies:
  - name: common
    version: 1.0.0
    repository: file://../../common
```

Run `helm dependency build` to download the dependency.

### 3. Create Standardized values.yaml

Create `values.yaml` with the standardized structure (see [Values Structure](#values-structure) below).

### 4. Create Template File

Use a single template file that includes all resources:

```yaml
# templates/common.yaml
{{ include "common.all" . }}
```

The `common.all` helper automatically includes all standard resources based on your `values.yaml` configuration. Resources are only rendered if their corresponding values are defined and enabled.

**Alternative: Individual Templates**

If you need more control, you can use individual template files instead:

```yaml
# templates/deployment.yaml
{{ include "common.deployment" . }}

# templates/service.yaml
{{ include "common.service" . }}

# templates/pvc.yaml
{{ include "common.pvc" . }}

# templates/virtual-service.yaml
{{ include "common.virtualService" . }}
```

## Values Structure

The library expects a standardized `values.yaml` structure. Here's a complete example:

```yaml
# Image configuration
image:
  repository: docker.io/org/my-app
  tag: v1.0.0
  pullPolicy: IfNotPresent

# Subdomain for ingress
subdomain: my-app

# Deployment configuration
deployment:
  strategy: Recreate  # or RollingUpdate
  replicas: 1
  revisionHistoryLimit: 0  # Optional, defaults to 2. Set to 0 to disable history
  hostNetwork: false  # Optional, for host networking
  dnsPolicy: ClusterFirst  # Optional, for custom DNS policy
  name: ""  # Optional suffix for deployment name (e.g., "main" results in "{release}-main")

# Container configuration
container:
  # Single port (simple case)
  port: 8080
  
  # OR multiple ports (use array)
  ports:
    - name: http
      port: 8080
      protocol: TCP
    - name: grpc
      port: 9090
      protocol: TCP
  
  # Health probe configuration
  healthProbe:
    type: httpGet  # or tcpSocket
    port: http  # Use named port or number
    path: /health  # Required for httpGet
    # Optional: initialDelaySeconds, periodSeconds, etc.
  
  # Resource limits (optional)
  resources:
    limits:
      cpu: "1000m"
      memory: "512Mi"
    requests:
      cpu: "500m"
      memory: "256Mi"
  
  # Security context (optional)
  securityContext:
    privileged: false
    runAsUser: 1000
    runAsGroup: 1000

# Init Containers (optional)
# Add init containers, for example to fix permissions
initContainers:
  - name: fix-permissions
    image: busybox
    command: ["sh", "-c", "chown -R 1000:1000 /data"]
    volumeMounts:
      - name: data
        mountPath: /data
    securityContext:
      runAsUser: 0

# Command and args (optional)
# Override the container's default command/entrypoint
# Useful for initialization scripts or custom startup logic
command:
  - /bin/sh
  - -c
args:
  - |
    echo "Running initialization..."
    # Your custom startup logic here
    exec /app/start.sh

# Service configuration
service:
  # Single service (simple case)
  port: 80
  targetPort: 8080  # Optional, defaults to container port
  type: ClusterIP
  
  # OR multiple services (use array)
  ports:
    - name: http
      port: 80
      targetPort: 8080
      protocol: TCP
      type: ClusterIP
    - name: grpc
      port: 9090
      targetPort: 9090
      protocol: TCP
      type: ClusterIP
      serviceName: grpc  # Creates separate service: {release}-grpc

# Volume configuration
volumes:
  - name: data
    mountPath: /data
    persistentVolumeClaim: data  # References PVC from persistentVolumeClaims
  - name: config
    mountPath: /config
    emptyDir: {}  # For temporary/ephemeral storage
  - name: external
    mountPath: /external
    persistentVolumeClaim: external-pvc  # External PVC (not prefixed with release name)

# Persistent volume claims
persistentVolumeClaims:
  - name: data
    size: 10Gi
  - name: cache
    size: 5Gi

# VirtualService configuration (Istio)
virtualService:
  enabled: true
  gateways:
    public: true   # Enable public gateway
    private: true  # Enable private gateway
  servicePort: 80  # Optional, defaults to service port

# OIDC client configuration (optional)
oidc:
  enabled: true
  redirectUris:
    - "/api/auth/callback/authentik"
    - "/oauth/oidc/callback"
  subjectMode: user_username  # Optional: user_username (default), user_email, user_id

# Database configuration (optional)
database:
  enabled: true

# External secrets configuration (optional)
externalSecrets:
  - name: "{release}-secrets"  # Use {release} placeholder
    passwords:
      - name: apiKey
        length: 32
        encoding: hex  # Supported: base64, base64url, base32, hex, raw
        allowRepeat: true
        secretKeys:  # Required: sets the key name in the secret
          - apiKey
      - name: encryptionKey
        length: 64
        encoding: base64
        allowRepeat: false
        secretKeys:  # Required: sets the key name in the secret
          - encryptionKey

# Environment variables
env:
  # Simple value
  APP_NAME: "My App"
  
  # Using placeholders
  BASE_URL:
    value: "https://{subdomain}.{domain}"
  TZ:
    value: "{timezone}"
  
  # Secret references
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "{release}-connection"
        key: url
  OAUTH_CLIENT_ID:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"
        key: clientId
  API_KEY:
    valueFrom:
      secretKeyRef:
        name: "{release}-secrets"
        key: apiKey
```

## Template Files

### Recommended: Single Template with `common.all`

The simplest approach is to use a single template file:

```yaml
# templates/common.yaml
{{ include "common.all" . }}
```

This automatically renders all resources based on your `values.yaml`:
- **Deployment** - always rendered if `deployment` is defined
- **Service** - always rendered if `service` is defined
- **ServiceAccount** - rendered if `serviceAccount` is defined
- **PVC** - rendered if `persistentVolumeClaims` is defined
- **VirtualService** - rendered if `virtualService.enabled: true`
- **DNS** - rendered if `dns.enabled: true`
- **OIDC** - rendered if `oidc.enabled: true`
- **Database** - rendered if `database.enabled: true`
- **ExternalSecrets** - rendered if `externalSecrets` is defined

### Alternative: Individual Templates

For more control or custom resources, use individual template files:

```yaml
# templates/deployment.yaml
{{ include "common.deployment" . }}

# templates/service.yaml
{{ include "common.service" . }}

# templates/pvc.yaml
{{ include "common.pvc" . }}

# templates/virtual-service.yaml
{{ include "common.virtualService" . }}

# templates/client.yaml (OIDC)
{{ include "common.oidc" . }}

# templates/database.yaml
{{ include "common.database" . }}

# templates/secret-password-generators.yaml
{{ include "common.externalSecrets.passwordGenerators" . }}

# templates/secret-external-secrets.yaml
{{ include "common.externalSecrets.externalSecrets" . }}
```

**Note:** Remember to include `secretKeys` in each password configuration in `values.yaml` to set the key names in the generated secret. See the [External Secrets](#external-secrets) section for details.

## Complete Examples

### Example 1: Simple Stateless Application

```yaml
# values.yaml
image:
  repository: docker.io/org/my-app
  tag: v1.0.0
  pullPolicy: IfNotPresent

subdomain: my-app

deployment:
  strategy: RollingUpdate
  replicas: 2

container:
  port: 8080
  healthProbe:
    type: httpGet
    path: /health
    port: 8080

service:
  port: 80
  type: ClusterIP

virtualService:
  enabled: true
  gateways:
    public: true

env:
  TZ:
    value: "{timezone}"
```

```yaml
# templates/common.yaml
{{ include "common.all" . }}
```

### Example 2: Application with OIDC and Database

```yaml
# values.yaml
image:
  repository: docker.io/org/my-app
  tag: v1.0.0
  pullPolicy: IfNotPresent

subdomain: my-app

deployment:
  strategy: Recreate
  replicas: 1

container:
  port: 8080
  healthProbe:
    type: tcpSocket
    port: 8080

service:
  port: 80
  type: ClusterIP

volumes:
  - name: data
    mountPath: /data
    persistentVolumeClaim: data

persistentVolumeClaims:
  - name: data
    size: 10Gi

virtualService:
  enabled: true
  gateways:
    public: true
    private: true

oidc:
  enabled: true
  redirectUris:
    - "/api/auth/callback/authentik"
  subjectMode: user_username

database:
  enabled: true

env:
  TZ:
    value: "{timezone}"
  BASE_URL:
    value: "https://{subdomain}.{domain}"
  OAUTH_CLIENT_ID:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"
        key: clientId
  OAUTH_CLIENT_SECRET:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"
        key: clientSecret
  OAUTH_ISSUER_URL:
    valueFrom:
      secretKeyRef:
        name: "{release}-oidc-credentials"
        key: issuer
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "{release}-connection"
        key: url
```

```yaml
# templates/common.yaml
{{ include "common.all" . }}
```

### Example 3: Application with Generated Secrets

```yaml
# values.yaml
# ... other configuration ...

externalSecrets:
  - name: "{release}-secrets"
    passwords:
      - name: encryptionKey
        length: 64
        encoding: base64
        allowRepeat: true
        secretKeys:  # Required: sets the key name in the secret
          - encryptionKey
      - name: apiToken
        length: 32
        encoding: hex
        allowRepeat: false
        secretKeys:  # Required: sets the key name in the secret
          - apiToken

env:
  ENCRYPTION_KEY:
    valueFrom:
      secretKeyRef:
        name: "{release}-secrets"
        key: encryptionKey
  API_TOKEN:
    valueFrom:
      secretKeyRef:
        name: "{release}-secrets"
        key: apiToken
```

```yaml
# templates/common.yaml
{{ include "common.all" . }}
```

## Available Templates

The library provides full resource templates that can be included directly:

- **`common.all`** - All-in-one template that renders all resources based on values (recommended)
- `common.deployment` - Full Deployment resource with all standard configurations (supports custom command/args)
- `common.service` - Full Service resource(s) - supports multiple services
- `common.serviceAccount` - Full ServiceAccount resource
- `common.pvc` - Full PVC resources - supports multiple PVCs
- `common.virtualService` - Full VirtualService resources (public + private gateways)
- `common.dns` - Full DNSRecord resource
- `common.oidc` - Full AuthentikClient resource for OIDC authentication
- `common.database` - Full PostgresDatabase resource for database provisioning
- `common.externalSecrets` - Combined Password generators + ExternalSecret resources
- `common.externalSecrets.passwordGenerators` - Password generator resources only
- `common.externalSecrets.externalSecrets` - ExternalSecret resources only

## Secret References

### OIDC Credentials

When `oidc.enabled: true`, the AuthentikClient creates a secret named `{release}-oidc-credentials` with:
- `clientId` - OAuth client ID
- `clientSecret` - OAuth client secret
- `issuer` - OIDC provider issuer URL

### Database Connection

When `database.enabled: true`, the PostgresDatabase creates a secret named `{release}-connection` with:
- `url` - Complete PostgreSQL connection URL
- `host` - Database hostname
- `port` - Database port
- `database` - Database name
- `user` - Database username
- `password` - Database password

### External Secrets

External secrets are created with the name specified in `externalSecrets[].name` (use `{release}` placeholder). 

**Important:** The `secretKeys` field is **required** for each password generator to set the key name in the secret. Without `secretKeys`, the Password generator defaults to using `password` as the key name. The `name` field in the password config is used for the generator name, not the secret key name.

**Supported encodings:** `base64`, `base64url`, `base32`, `hex`, `raw` (note: `alphanumeric` is not supported)

**Example:**
```yaml
externalSecrets:
  - name: "{release}-secrets"
    passwords:
      - name: my-password-generator  # Generator name (used in resource name)
        length: 32
        encoding: hex
        allowRepeat: true
        secretKeys:  # Required: sets the key name in the secret
          - mySecretKey  # This becomes the key name in the secret
```

The secret will contain a key named `mySecretKey` (not `my-password-generator`).

## Secret-based Configurations

When an application requires a configuration file (like `config.yaml` or `.env`) that contains sensitive data, you should generate a `Secret` using External Secrets templating instead of a `ConfigMap`. This keeps the sensitive data encrypted in ETCD while allowing you to merge static and dynamic values.

### 1. Create an External Secret with a Template
Create a custom template in your chart (e.g., `templates/external-config.yaml`):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "common.fullname" . }}-config
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend # Replace with your SecretStore name
    kind: SecretStore
  target:
    name: {{ include "common.fullname" . }}-config
    template:
      engineVersion: v2
      data:
        config.yaml: |
          server:
            port: 8080
          database:
            user: {{ "{{" }} .db_user | toString {{ "}}" }}
            password: {{ "{{" }} .db_pass | toString {{ "}}" }}
  data:
    - secretKey: db_user
      remoteRef:
        key: database/credentials
        property: username
    - secretKey: db_pass
      remoteRef:
        key: database/credentials
        property: password
```

### 2. Mount the Secret in values.yaml
Reference the generated secret in your `volumes` configuration using the `{release}` placeholder:

```yaml
volumes:
  - name: config
    mountPath: /app/config.yaml
    subPath: config.yaml
    secret: "{release}-config"
```

## Placeholders

Use placeholders in `values.yaml` for dynamic values that are resolved at template time:

- `{release}` - Release name (e.g., "my-app")
- `{namespace}` - Release namespace (e.g., "default")
- `{fullname}` - Full app name (same as release name)
- `{subdomain}` - Application subdomain (from `subdomain` value)
- `{domain}` - Global domain (from `globals.domain`)
- `{timezone}` - Global timezone (from `globals.timezone`)

**Example:**

```yaml
env:
  BASE_URL:
    value: "https://{subdomain}.{domain}"
  SECRET_NAME:
    value: "{release}-secrets"
```

## Advanced Configuration

### Multiple Services

Define multiple services using the `ports` array:

```yaml
service:
  ports:
    - name: http
      port: 80
      targetPort: 8080
      type: ClusterIP
    - name: grpc
      port: 9090
      targetPort: 9090
      type: ClusterIP
      serviceName: grpc  # Creates separate service: {release}-grpc
```

### Multiple Ports

Define multiple container ports:

```yaml
container:
  ports:
    - name: http
      port: 8080
      protocol: TCP
    - name: metrics
      port: 9090
      protocol: TCP
```

### Custom Deployment Name

Use a suffix for the deployment name:

```yaml
deployment:
  name: "main"  # Results in deployment name: {release}-main
```

This also affects service selectors and virtual service destinations.

### Host Networking

Enable host networking:

```yaml
deployment:
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
```

### Privileged Containers

Run containers in privileged mode:

```yaml
container:
  securityContext:
    privileged: true
```

### Resource Limits

Set CPU and memory limits:

```yaml
container:
  resources:
    limits:
      cpu: "2000m"
      memory: "2Gi"
    requests:
      cpu: "1000m"
      memory: "1Gi"
```

## Custom Templates

For application-specific resources that aren't covered by the common library, create custom templates. You can still use helper functions:

```yaml
# templates/custom-resource.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "common.fullname" . }}-config
  labels:
    {{- include "common.labels" . | nindent 4 }}
data:
  config.yaml: |
    # Custom configuration
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

## Best Practices

1. **Always use placeholders** for dynamic values (`{release}`, `{subdomain}`, `{domain}`, `{timezone}`)
2. **Use named ports** when defining multiple ports (e.g., `port: http` instead of `port: 8080`)
3. **Set `revisionHistoryLimit: 0`** for stateful applications using Recreate strategy
4. **Reference secrets** using the `{release}` placeholder in secret names
5. **Use the standardized structure** - it makes charts consistent and easier to maintain
6. **Keep custom templates minimal** - only for truly application-specific resources

## Testing

After creating your chart:

1. Build dependencies: `helm dependency build`
2. Lint: `helm lint .`
3. Template: `helm template my-app . --set globals.environment=prod --set globals.domain=example.com ...`
4. Dry-run: `helm install my-app . --dry-run --debug`

## Documentation

- **[MIGRATION.md](./MIGRATION.md)** - Complete guide for migrating existing charts
- **[TEMPLATING.md](./TEMPLATING.md)** - Detailed guide to using placeholders in values.yaml

## Examples

See migrated charts for real-world examples:
- `apps/charts/komga` - Simple application using `common.all`
- `apps/charts/homarr` - Application with OIDC and external secrets using `common.all`
- `apps/charts/n8n` - Complex application with multiple services
- `apps/charts/home-assistant` - Application with host networking and privileged containers
