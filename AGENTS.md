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

### 2. Core Templates

#### Deployment Template
Create `templates/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "{{ .Release.Name }}"
spec:
  strategy:
    type: Recreate
  replicas: 1
  revisionHistoryLimit: 0
  selector:
    matchLabels:
      app: "{{ .Release.Name }}"
  template:
    metadata:
      labels:
        app: "{{ .Release.Name }}"
    spec:
      containers:
        - name: "{{ .Release.Name }}"
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: "{{ .Values.image.pullPolicy }}"
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          livenessProbe:
            tcpSocket:
              port: http
          readinessProbe:
            tcpSocket:
              port: http
          volumeMounts:
            - mountPath: /data
              name: data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: "{{ .Release.Name }}-data"
```

#### Service Template
Create `templates/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: "{{ .Release.Name }}"
spec:
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: "{{ .Release.Name }}"
```

#### Persistent Volume Claim
Create `templates/pvc.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "{{ .Release.Name }}-data"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

## Custom Resource Definitions (CRDs)

This project uses several custom resources that are managed by operators in the cluster:

### 1. OIDC Client (OpenID Connect Authentication)

The `OidcClient` resource automatically provisions OAuth2/OIDC clients with your identity provider.

Create `templates/client.yaml`:
```yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: OidcClient
metadata:
  name: '{{ .Release.Name }}'
spec:
  environment: '{{ .Values.globals.environment }}'
  redirectUris:
    - path: /oauth/oidc/callback
      subdomain: '{{ .Values.subdomain }}'
      matchingMode: strict
```

**What it does:**
- Creates an OIDC client in your identity provider (e.g., Authentik)
- Generates a Kubernetes secret named `{{ .Release.Name }}-client` containing:
  - `clientId`: The OAuth client ID
  - `clientSecret`: The OAuth client secret
  - `configuration`: The OIDC provider URL

**Using in deployment:**
```yaml
env:
  - name: OAUTH_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: "{{ .Release.Name }}-client"
        key: clientId
  - name: OAUTH_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: "{{ .Release.Name }}-client"
        key: clientSecret
  - name: OPENID_PROVIDER_URL
    valueFrom:
      secretKeyRef:
        name: "{{ .Release.Name }}-client"
        key: configuration
```

### 2. PostgreSQL Database

The `PostgresDatabase` resource automatically provisions PostgreSQL databases.

Create `templates/database.yaml`:
```yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: PostgresDatabase
metadata:
  name: '{{ .Release.Name }}'
spec:
  environment: '{{ .Values.globals.environment }}'
```

**What it does:**
- Creates a PostgreSQL database with the same name as your release
- Creates a user with appropriate permissions
- Generates a Kubernetes secret named `{{ .Release.Name }}-database` containing:
  - `url`: Complete PostgreSQL connection URL
  - `host`: Database hostname
  - `port`: Database port
  - `database`: Database name
  - `username`: Database username
  - `password`: Database password

**Using in deployment:**
```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: "{{ .Release.Name }}-database"
        key: url
```

### 3. Secret Generation

The `GenerateSecret` resource creates secure random secrets.

Create `templates/secret.yaml`:
```yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: GenerateSecret
metadata:
  name: "{{ .Release.Name }}-secrets"
spec:
  fields:
    - name: encryptionkey
      encoding: hex      # Options: hex, base64, alphanumeric
      length: 64        # Length in bytes (before encoding)
    - name: apitoken
      encoding: base64
      length: 32
```

**What it does:**
- Generates cryptographically secure random values
- Creates a Kubernetes secret with the specified fields
- Supports different encoding formats for different use cases

**Using in deployment:**
```yaml
env:
  - name: ENCRYPTION_KEY
    valueFrom:
      secretKeyRef:
        name: "{{ .Release.Name }}-secrets"
        key: encryptionkey
```

### 4. External HTTP Service

The `ExternalHttpService` resource configures ingress routing for your application.

Create `templates/external-http-service.yaml`:
```yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: ExternalHttpService
metadata:
  name: '{{ .Release.Name }}'
spec:
  environment: '{{ .Values.globals.environment }}'
  subdomain: '{{ .Values.subdomain }}'
  destination:
    host: '{{ .Release.Name }}.{{ .Release.Namespace }}.svc.cluster.local'
    port:
      number: 80
```

**What it does:**
- Creates ingress routes for your application
- Configures subdomain routing (e.g., `myapp.yourdomain.com`)
- Handles TLS termination automatically
- Integrates with your service mesh (if applicable)

## Best Practices

### 1. Naming Conventions
- Use `{{ .Release.Name }}` consistently for all resource names
- Suffix resource names appropriately: `-data`, `-secrets`, `-client`, `-database`

### 2. Container Configuration
- Always specify health checks (liveness and readiness probes)
- Use named ports (e.g., `http`, `grpc`) instead of port numbers
- Set `revisionHistoryLimit: 0` to prevent accumulation of old ReplicaSets

### 3. Environment Variables
- Never hardcode secrets in values.yaml
- Use secretKeyRef to reference generated secrets
- Group related environment variables together

### 4. Persistent Storage
- Always use PVCs for stateful data
- Consider storage requirements carefully (start with reasonable defaults)
- Mount data at standard paths for the application

### 5. OIDC Integration
- Set `ENABLE_SIGNUP: "false"` if using OIDC
- Enable OIDC signup with `ENABLE_OAUTH_SIGNUP: "true"`
- Configure email merging if needed with `OAUTH_MERGE_ACCOUNTS_BY_EMAIL`

### 6. Database Usage
- Only include database.yaml if the app needs PostgreSQL
- Applications should support DATABASE_URL environment variable
- Consider connection pooling settings for production

## Disabling Applications

To temporarily disable an application, rename its directory with `.disabled` suffix:
```bash
mv apps/charts/my-app apps/charts/my-app.disabled
```

The ArgoCD ApplicationSet will automatically exclude directories matching `*.disabled`.

## Testing Your Chart

1. **Lint your chart:**
   ```bash
   helm lint apps/charts/my-app
   ```

2. **Render templates locally:**
   ```bash
   helm template my-app apps/charts/my-app
   ```

3. **Dry run installation:**
   ```bash
   helm install my-app apps/charts/my-app --dry-run --debug
   ```

## Deployment Workflow

**IMPORTANT:** There is no test environment. When creating or modifying applications:

1. **Make changes directly to the files** - The agent will write changes to the actual chart files
2. **User deploys the changes** - After changes are made, the user must deploy them to the cluster
3. **Debug with kubectl** - If issues arise after deployment, agents can use kubectl to:
   - Check pod status and logs
   - Inspect generated resources
   - Verify secret creation
   - Troubleshoot configuration issues

**Note:** Agents cannot deploy applications themselves. They can only:
- Create and modify chart files
- Use kubectl to investigate deployment issues
- Provide debugging assistance and recommendations

## Common Patterns

### Application with OIDC + Database
For apps requiring both authentication and database:
- Include `client.yaml` for OIDC
- Include `database.yaml` for PostgreSQL
- Reference both secrets in deployment

### Stateless Applications
For simple stateless apps:
- Omit `pvc.yaml`
- Remove volume mounts from deployment
- Consider using `Deployment` scaling if appropriate

### Background Services
For services without web interface:
- Omit `external-http-service.yaml`
- Omit `client.yaml` (no OIDC needed)
- Focus on service discovery within cluster

## Troubleshooting

### Secret Not Found
If secrets are not being created:
1. Check that the CRD controller is running
2. Verify the `environment` value matches your setup
3. Check controller logs for provisioning errors

### OIDC Issues
1. Verify redirect URIs match exactly
2. Check that the identity provider is accessible
3. Ensure the client secret is being properly mounted

### Database Connection
1. Verify the database operator is running
2. Check network policies between namespaces
3. Ensure the database server has capacity

## Global Values

Applications can access global values through `{{ .Values.globals }}`:
- `environment`: The deployment environment (e.g., "production", "staging")
- Additional values can be added at the root chart level

## Maintenance

### Updating Images
1. Update the tag in `values.yaml`:
   ```yaml
   tag: v1.0.0  # Use semantic version tags only
   ```
2. **Note:** Do not include SHA digests in tags. Immutable digests are automatically added later by Renovate

### Renovate Integration
The project uses Renovate for automated dependency updates. Configure in `renovate.json5` to:
- Auto-update container images
- Create pull requests for updates
- Group related updates

### Backup Considerations
For applications with persistent data:
1. Consider implementing backup CronJobs
2. Use volume snapshots if available
3. Export data regularly for critical applications

## Contributing

When adding new applications:
1. Follow the existing patterns and conventions
2. Document any special requirements in the chart's README
3. Consider security implications of all configurations
4. Update this document if introducing new patterns

## Maintaining This Document

**IMPORTANT:** When making changes to the project structure, patterns, or custom resources:
- Keep this AGENTS.md file up to date with any changes
- Document new CRDs or custom resources as they are added
- Update examples if the patterns change
- Add new sections for significant new features or patterns
- Ensure all code examples remain accurate and tested

This document serves as the primary reference for creating and maintaining applications in this project. Keeping it current ensures consistency and helps onboard new contributors.