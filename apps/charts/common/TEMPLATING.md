# Values Templating Guide

This document explains how templating works in `values.yaml` files and what placeholders are available.

## Current Placeholders

The templating system supports the following placeholders in `values.yaml`:

| Placeholder | Maps To | Example |
|------------|---------|---------|
| `{release}` | `.Release.Name` | `forgejo`, `audiobookshelf` |
| `{namespace}` | `.Release.Namespace` | `prod`, `default` |
| `{fullname}` | `common.fullname` helper | `audiobookshelf`, `forgejo` |
| `{subdomain}` | `.Values.subdomain` | `code`, `audiobookshelf` |
| `{domain}` | `.Values.globals.domain` | `olsen.cloud` |
| `{timezone}` | `.Values.globals.timezone` | `Europe/Amsterdam` |

## Available Values

### Release Object (`.Release.*`)
- `.Release.Name` - The release name (chart instance name)
- `.Release.Namespace` - The namespace the release will be installed into
- `.Release.Service` - The service that rendered the chart (usually "Helm")
- `.Release.Revision` - The revision number of this release

### Chart Object (`.Chart.*`)
- `.Chart.Name` - The name of the chart
- `.Chart.Version` - The version of the chart
- `.Chart.AppVersion` - The app version of the chart

### Values Object (`.Values.*`)
- `.Values.subdomain` - The subdomain for this application
- `.Values.globals.environment` - The environment (e.g., `prod`)
- `.Values.globals.domain` - The domain (e.g., `olsen.cloud`)
- `.Values.globals.timezone` - The timezone (e.g., `Europe/Amsterdam`)
- `.Values.globals.istio.gateways.public` - Public Istio gateway
- `.Values.globals.istio.gateways.private` - Private Istio gateway
- `.Values.globals.authentik.ref.name` - Authentik server name
- `.Values.globals.authentik.ref.namespace` - Authentik server namespace
- `.Values.globals.networking.private.ip` - Private network IP

## Usage Examples

### Simple String Replacement

```yaml
env:
  BASE_URL:
    value: "https://{subdomain}.{domain}"
  # Renders to: "https://audiobookshelf.olsen.cloud"
```

### Secret Reference with Release Name

```yaml
env:
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "{release}-database"
        key: url
  # Renders to: name: "audiobookshelf-database"
```

### Complex String with Multiple Placeholders

```yaml
env:
  SSH_DOMAIN:
    value: "ssh-{subdomain}.{domain}"
  # Renders to: "ssh-code.olsen.cloud"
```

## Extending Placeholders

To add more placeholders, edit `apps/charts/common/templates/_helpers.tpl` in the `common.env` helper:

### Current Implementation

```go
value: {{ $value 
  | replace "{release}" $.Release.Name 
  | replace "{namespace}" $.Release.Namespace
  | replace "{fullname}" (include "common.fullname" $)
  | replace "{subdomain}" $.Values.subdomain 
  | replace "{domain}" $.Values.globals.domain
  | replace "{timezone}" $.Values.globals.timezone
  | quote }}
```

**Note:** `{fullname}` uses the `common.fullname` helper which:
- Returns `.Release.Name` if it contains the chart name
- Otherwise returns `{release}-{chart-name}`
- Respects `.Values.fullnameOverride` if set

**Important:** Update both locations:
1. Line ~245: For `value:` entries (when `$value.value` exists)
2. Line ~248: For simple string values

### Example Usage

```yaml
env:
  NAMESPACE:
    value: "{namespace}"
  # Renders to: "prod" (or whatever namespace the release is in)
  
  TIMEZONE:
    value: "{timezone}"
  # Renders to: "Europe/Amsterdam"
  
  APP_NAME:
    value: "{fullname}"
  # Renders to: "audiobookshelf" (or "release-chartname" if different)
  
  FULL_URL:
    value: "https://{subdomain}.{domain}"
  # Renders to: "https://audiobookshelf.olsen.cloud"
  
  SECRET_NAME:
    valueFrom:
      secretKeyRef:
        name: "{fullname}-secrets"
        key: apiKey
  # Renders to: name: "audiobookshelf-secrets"
```

## Limitations

1. **No nested placeholders**: Placeholders cannot reference other placeholders
2. **No conditional logic**: Placeholders are simple string replacements
3. **No functions**: Cannot use Helm template functions in values.yaml
4. **Order matters**: Replacements happen in order, so `{release}` is replaced before `{subdomain}`

## Best Practices

1. **Use placeholders for dynamic values**: Release names, domains, subdomains
2. **Keep it simple**: Use placeholders for common values, not complex logic
3. **Document custom placeholders**: If you add new ones, document them
4. **Test thoroughly**: Verify placeholders render correctly in your environment

## Troubleshooting

If a placeholder isn't being replaced:

1. Check the placeholder name matches exactly (case-sensitive)
2. Verify the value exists in the context (`.Release.*` or `.Values.*`)
3. Check the replacement chain in `_helpers.tpl`
4. Use `helm template --debug` to see the rendered output
