# workforce

Agents built once and served as ACP agents over WebSocket
([repository](https://code.olsen.cloud/morten-olsen/workforce)), at `https://workforce.olsen.cloud`
on the private gateway.

- **Server:** the Deployment `workforce`, its SQLite database on the `workforce-data` claim
  (backed up). Recreate strategy: never two writers.
- **Sealing key:** `WORKFORCE_SECRET_KEY` in `workforce-keys`, generated once by External Secrets
  and orphaned, so pruning never deletes it. Losing it makes every stored secret unreadable.
- **Sign-in:** `AuthentikClient` `workforce`, a public client with the device code and refresh
  grants for `workforce login`; the group `gitops/prod/workforce` (add people as `oidc.members`)
  makes users, `shared/admin` makes admins.
- **Computers:** the kubecomputer client `workforce` (apps chart kubecomputer) writes its URL,
  namespace and key to `workforce-kubecomputer`, which the server reads. A kubecomputer provider
  created with no settings of its own uses them:

  ```sh
  api providers -d '{"name":"homelab","kind":"kubecomputer","config":{}}'
  ```

- **Route:** no timeout and no retries, so agents' WebSockets stay open.

`workforce login` needs a device code flow on the Authentik brand (Admin, System, Brands).
