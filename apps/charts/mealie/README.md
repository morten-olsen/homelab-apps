# Mealie authentication

Mealie links OIDC sign-ins to its existing accounts by verified email. Keep
`OIDC_REQUIRES_EMAIL_VERIFICATION=true`. Authentik's standard `profile` mapping
supplies name, username and groups; its `openid` mapping supplies protocol scope
support. The dedicated `mealie-email` scope supplies email and verification.
Both the AuthentikClient scopes and Mealie's requested scopes must stay aligned.

## Approved identity and mapping

Task `842a05bd-9c04-4b06-a390-acf65155ebe2` records Morten's approval to assert
verification only for active Authentik user ID `7`, username `morten`, exact
address `morten@olsen.pro`. An account with a different ID, username or address
receives `email_verified=false`; so does an inactive account. Adding another
identity or changing this policy requires a new decision and Security review.
This is an explicit owner attestation, not automated proof of mailbox ownership.

The approved expression is in `scripts/reconcile-email-mapping.py`. It creates
only `prod-mealie verified email`, with scope `mealie-email`, and refuses
duplicate scopes (case-insensitive, matching the operator), noncanonical scope
spelling, name collisions, managed mappings, an unexpected identity,
or a mapping attached to another provider. It never edits a shared mapping,
provider, user, password, or Mealie database.

## Provisioning and rollout

From the repository root, check without writes:

```sh
python3 apps/charts/mealie/scripts/reconcile-email-mapping.py
```

After authentication approval and Security review, provision the mapping before
merging this chart's scope selection:

```sh
python3 apps/charts/mealie/scripts/reconcile-email-mapping.py --apply
```

The tool uses `kubectl exec` and `ak shell` on the existing Authentik server.
Check mode uses an explicitly read-only PostgreSQL transaction. Apply mode is a
documented authentication configuration recovery action, not a database schema
migration or a maintenance Job. It does not read or print Secret values.
The mapping persists in Authentik's database; changes to its reviewed expression
must be applied with this command. Git records the expression, while ArgoCD and
the existing operator continuously reconcile provider scope selection. The
operator selects mappings by scope name, so `mealie-email` must remain unique.

Verify the Forgejo build and mirror, Mealie's expected ArgoCD revision, its ready
pod and live scopes/verification setting. Check that `prod-mealie` has exactly
one email-producing mapping (`mealie-email`), with no ordinary `email` mapping.
Check the approved and negative cases against Authentik's actual expression
evaluator. Finally Morten must sign in through Authentik and confirm the existing
administrator account and recipes. Healthy pods alone do not verify sign-in.

Validate locally with the repository's chart gate:

```sh
mise exec -- scripts/ci/validate-charts.sh apps/charts/mealie
```

Python is pinned in the repository's `mise.toml` so these policy tests also run
in the existing Woodpecker chart gate.

## Recovery and rollback

The incident occurred with two mappings for the ordinary `email` scope: an
unconditional custom `true` claim and the managed default `false` claim. The
operator selects both when a client requests `email`, so a manual deselection
does not survive reconciliation. The dedicated scope avoids this conflict for
Mealie without changing other providers.

Revert this chart change through Forgejo to restore the previous requested and
provider scopes. This restores the diagnosed login rejection; it does not reset
credentials or change data. The unused dedicated mapping can remain inert.
Do not repurpose a shared email mapping or disable verification to recover.
