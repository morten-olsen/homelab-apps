# workforce

Agents built once and served as ACP agents over WebSocket
([repository](https://code.olsen.cloud/morten-olsen/workforce)). For now the chart only makes
workforce's OIDC client, so a server run elsewhere can use it; the Deployment follows once the
server has an image.

- `AuthentikGroup` `workforce`: workforce's users, the Authentik group `gitops/prod/workforce`.
  Add people as `oidc.members`.
- `AuthentikClient` `workforce`: a public client with the device code and refresh grants, for
  `workforce login`. Members of `shared/admin` may sign in too, and are workforce admins.

The operator writes the client to the Secret `workforce-oidc-credentials` in `prod`. A server run
outside the cluster takes its settings from there:

```sh
secret() { kubectl -n prod get secret workforce-oidc-credentials -o "jsonpath={.data.$1}" | base64 -d; }
export WORKFORCE_OIDC_ISSUER="$(secret issuer)"
export WORKFORCE_OIDC_CLIENT_ID="$(secret clientId)"
export WORKFORCE_OIDC_USER_GROUP=gitops/prod/workforce
export WORKFORCE_OIDC_ADMIN_GROUP=gitops/shared/admin
```

`workforce login` needs a device code flow on the Authentik brand (Admin, System, Brands);
without one, Authentik hands out codes but its `/device` page cannot take them.
