# Agent Documentation

This document describes how to create a new application chart for the homelab operator.

## Chart Structure

Each application has its own chart located in a directory under `charts/apps`. The chart should contain the following files:

- `Chart.yaml`: The chart metadata.
- `values.yaml`: The default values for the chart.
- `templates/`: A directory containing the Kubernetes resource templates.

## Custom Resources

The homelab operator uses several custom resources to manage applications. These resources are defined in the `templates` directory of the chart.

### `PostgresDatabase`

If the application requires a PostgreSQL database, you can create a `PostgresDatabase` resource. The operator will automatically create a database and a secret containing the connection details. The secret will have the same name as the release with a `-pg-connection` postfix.

Example:

```yaml
# templates/database.yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: PostgresDatabase
metadata:
  name: "{{ .Release.Name }}"
spec:
  environment: "{{ .Values.globals.environment }}"
```

The secret has the following values:

- `database`: name of the created database
- `host`: the hostname of the postgres server
- `port`: the port of the postgres server
- `url`: combined url in the format `postgresql://{user}:{password}@{host}:{port}/{database}`

### `OidcClient`

If the application requires OIDC authentication, you can create an `OidcClient` resource. The operator will automatically create an OIDC client and a secret containing the client ID and secret. The secret will have the same name as the release with a `-client` postfix.

You need to specify the redirect URIs for the OIDC client. The subdomain is taken from the `values.yaml` file.

Example:

```yaml
# templates/client.yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: OidcClient
metadata:
  name: "{{ .Release.Name }}"
spec:
  environment: "{{ .Values.globals.environment }}"
  redirectUris:
    - path: /user/oauth2/Authentik/callback
      subdomain: "{{ .Values.subdomain }}"
      matchingMode: strict
```

The secret has the following value:

- `authorization`: Authorization endpoint
- `clientId`
- `clientSecret`
- `configuration`: autodiscovery endpoint
- `configurationIssuer`: issuer url
- `endSession`: end session endpoint
- `jwks`: jwks endpoint
- `token`: token endpoint
- `userinfo`: user info endpoint

### `HttpService` and `ExternalHttpService`

To expose the application, you can use either an `HttpService` or an `ExternalHttpService` resource.

- `HttpService`: This will expose the application through the Istio gateway. This is for internal access only.
- `ExternalHttpService`: This will expose the application through a CloudFlare tunnel. This is for external access.

Both resources take a `subdomain` and a `destination` as parameters. The `destination` is the Kubernetes service to route traffic to.

Example of `HttpService`:

```yaml
# templates/http-service.yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: HttpService
metadata:
  name: "{{ .Release.Name }}"
spec:
  environment: "{{ .Values.globals.environment }}"
  subdomain: "{{ .Values.subdomain }}"
  destination:
    host: "{{ .Release.Name }}.{{ .Release.Namespace }}.svc.cluster.local"
    port:
      number: 80
```

Example of `ExternalHttpService`:

```yaml
# templates/external-http-service.yaml
apiVersion: homelab.mortenolsen.pro/v1
kind: ExternalHttpService
metadata:
  name: "{{ .Release.Name }}"
spec:
  environment: "{{ .Values.globals.environment }}"
  subdomain: "{{ .Values.subdomain }}"
  destination:
    host: "{{ .Release.Name }}.{{ .Release.Namespace }}.svc.cluster.local"
    port:
      number: 80
```

## `values.yaml`

The `values.yaml` file should contain the following values:

- `globals.environment`: The environment the application is running in (e.g., `prod`, `dev`).
- `image.repository`: The Docker image repository.
- `image.tag`: The Docker image tag.
- `subdomain`: The subdomain for the application.

Example:

```yaml
# values.yaml
globals:
  environment: prod
image:
  repository: docker.gitea.com/gitea
  tag: latest
subdomain: gitea
```
