# Application access in GitOps

The common library 0.2.0 creates each application's AuthentikGroup and includes it
in AuthentikClient.allowedGroups. Group membership lives only in that chart's
values, not in a second Kubernetes resource or the Authentik UI:

```yaml
oidc:
  enabled: true
  group:
    members:
      - id: 123
        uuid: 11111111-2222-4333-8444-555555555555
  allowedGroups:
    - name: admin
      namespace: shared
```

Additional allowedGroups extends the app group. Empty app membership grants
nobody access through that group. Each migrated application explicitly
adds shared/admin, whose initial member is morten. Admin is a deployment group;
it does not give Authentik superuser or in-app administrator privileges. The
operator gives no implicit access to superusers.

NetBird and Dragonfly keep their existing custom client settings and use the
same group/membership helpers. Dragonfly's membership and grants use oidc values
alongside its custom authClient provider configuration; it does not enable a
second common-generated client.

Requires operator 0.2.0 and central shared/admin Ready before migrating a chart.
The operator leaves only un-migrated legacy clients on their earlier access
behavior; explicit empty lists, missing references and partial reconciliation
close managed applications. Once migrated, removing allowedGroups cannot reopen
access. UI edits to managed membership/bindings are drift. Deleted groups retain
their Authentik identity after membership revocation and cannot be recreated by
blind adoption.

Follow the base runbook docs/authentik-group-cutover.md and HOMEIT-474. Migrate
Mealie as the first canary, then one chart at a time under the agreed cutover.
Verify new authorization attempts before continuing. Existing app sessions and
issued tokens must be reported separately. Rollback needs an explicit safe
access plan; a chart revert does not undo Authentik binding state.

PR CI checks rendered migrated enrollments using scripts/ci/check-oidc-access.py.
For a local enrollment check after building dependencies, run
`scripts/tests/oidc-access.sh mealie` for the canary, or pass the names of the
applications in the current stage. With no arguments it checks all 17 migrations.
Publishing the new library and installing operator
CRDs are prerequisites, not steps this repository's CI can perform.
