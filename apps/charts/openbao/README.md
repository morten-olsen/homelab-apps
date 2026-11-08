# OpenBao: private, manually operated secrets service

This chart prepares GitOps resources, not an initialized secrets service. Nothing in
this runbook has been performed merely by adding the chart. **Deployment, ArgoCD
sync, Authentik membership/flow changes, initialization, unseal, auth/policy/secret
writes, revocation, pod replacement, restore and upgrades all require explicit
operator approval.** Read-only checks are identified separately below. Do not run
this document as a script.

## Deployment contract

- Official OpenBao Helm dependency **0.30.7**, server **2.7.2**, digest-pinned image;
  `homelab-common` **0.3.0** supplies platform integration only. Keep a matching
  `bao` 2.7.2 CLI on the trusted operator workstation.
- Namespace/release `prod` / `openbao`; StatefulSet `openbao`, pod `openbao-0`, API
  service `openbao:8200`, Raft data PVC `data-openbao-0` (10 GiB, `local-path`, RWO).
  The chart's `ha` switch selects its Raft template, **not actual HA**: one replica,
  one voting member, no failover. Node/disk loss or any restart causes an outage.
- Private URL **https://openbao.olsen.cloud**, Istio gateway `shared/private`,
  private DNS only, no public gateway and no Authentik forward-auth interception.
  OpenBao itself authenticates UI and API clients.
- The server's HTTP listener is allowed only inside its pod/mesh: explicit sidecar
  injection, a server-scoped `STRICT` PeerAuthentication and `ISTIO_MUTUAL`
  DestinationRule protect gateway-to-server traffic. Do not expose port 8200 as a
  NodePort, public LoadBalancer, plaintext ingress or non-mesh remote API. Use the
  private HTTPS address for workstation commands; do not set `BAO_SKIP_VERIFY`.
  Verify the actual sidecar and mTLS enforcement before sending credentials.
- Native Shamir seal with one key/one-share threshold and **manual unseal after
  every server restart**. No dev mode, auto-unseal, bootstrap Job, root-token
  Secret or stored Kubernetes unseal keys. Raft storage is `/openbao/data`.
- StatefulSet PVC retention is `Retain`; the data claim is protected from ArgoCD
  prune/deletion. These controls do not prevent a privileged human deleting a PVC,
  PV or node disk. Never approve removal of the Application/StatefulSet/PVC without
  a separately reviewed retention/recovery plan. Do not reinstall over missing
  storage or initialize a replacement until deciding whether to restore.
- No scheduled snapshot job, off-node backup delivery, restore rehearsal or audit
  sink is implied. The disabled injector is not a workload-secret integration.

Sources: [official Helm chart](https://github.com/openbao/openbao-helm),
[Raft storage](https://openbao.org/docs/configuration/storage/raft/),
[seal/unseal](https://openbao.org/docs/concepts/seal/),
[Istio STRICT mTLS](https://istio.io/latest/docs/reference/config/security/peer_authentication/).
Local `values.yaml` and templates are the deployment-specific authority.

## Local validation

From the apps repository, run:

```bash
mise exec -- scripts/ci/validate-charts.sh apps/charts/openbao
```

HOMEIT-533 validated the rendered private/mesh route, matching STRICT mTLS
selectors, retained claims and OIDC-registration toggle. An isolated local
container using the pinned image, rendered Raft HCL and pod privilege settings
passed init/unseal, scoped token permissions/expiry, native browser/device role
creation, SSH CA/signing restrictions, snapshot creation and persistence after
restart. Only synthetic local data was used; temporary containers/data were removed.
Real Authentik login, realized mesh isolation, retention lifecycle and snapshot
restore were not exercised. Local checks do not establish production readiness.

## Approval boundary and preflight

After review/approval, publish through the repository's normal GitOps process and
approve the generated ArgoCD Application sync. This change does not authorize a
commit, push or production sync. Do not run `helm install` alongside ArgoCD.

**Read-only, after approved deployment:**

```bash
kubectl -n prod get statefulset openbao
kubectl -n prod get pod openbao-0 -o jsonpath='{.spec.containers[*].name}{"\n"}'
kubectl -n prod get pvc data-openbao-0
kubectl -n prod get peerauthentication,destinationrule,virtualservice
kubectl -n prod get authentikclient openbao
export BAO_ADDR=https://openbao.olsen.cloud
bao version
bao status
```

Expect server container `openbao` and sidecar `istio-proxy`, bound retained storage,
private routing and matching mTLS policies. Before initialization the pod is
Running but not Ready: the native readiness check correctly fails while sealed.
`bao status` exit 2 means sealed, not necessarily a network error. Do not wait for
Ready before initializing/unsealing. Stop if the endpoint is public, TLS fails,
the sidecar is absent or non-mesh plaintext requests are accepted. Validating the
negative mTLS boundary requires an approved disposable client, not weakening
`STRICT`. [Status semantics](https://openbao.org/docs/commands/status/).

### Authentik prerequisites (not automatically proven by reconciliation)

The native `AuthentikClient` creates a dedicated confidential provider/application
and generated Secret `prod/openbao-oidc-credentials` (`clientId`, `clientSecret`,
`issuer`). Access is limited to its app group plus `shared/admin`; app eligibility
is **not** permission to administer OpenBao. Its subject mode is `user_uuid`, not
an email address/username; roles below use exact `sub` and group constraints.

Before setup, verify the reconciled provider has:

- Asymmetric signing using `authentik Self-signed Certificate`, published RSA JWKS
  and `RS256`; not HS256/client-secret signing. Native OpenBao validates discovery,
  issuer, audience and signatures; do not bypass discovery/JWKS validation.
- Only `openid`, `profile`, `email` scope mappings; `profile` supplies `groups`.
  No `offline_access`, no refresh-token expectation. Only authorization-code and
  `urn:ietf:params:oauth:grant-type:device_code` grants.
- Exact redirects `https://openbao.olsen.cloud/ui/vault/auth/oidc/oidc/callback`
  and `http://localhost:8250/oidc/callback`. The latter is a loopback callback,
  not a remotely exposed plaintext OpenBao API.
- An active Authentik **Brand device-code flow**, designation `Stage Configuration`,
  requiring authentication. Authentik does not supply this flow by default.
  Allowing the device grant or seeing a discovery endpoint is not proof this
  prerequisite is met. An Authentik administrator must verify it, and obtain
  approval before creating/assigning a flow or changing group membership.
- The actual UUID `sub` of each separately authorized human and exact emitted
  group names. Resolve these in the approved Authentik administrative view; do not
  paste ID/access tokens into online decoders or enable verbose OIDC token logging.
  Keep these non-secret identifiers in the operator's approved access record.

**Read-only discovery check** (prints no client secret):

```bash
ISSUER="$(kubectl -n prod get secret openbao-oidc-credentials \
  -o jsonpath='{.data.issuer}' | base64 --decode)"
curl --fail --silent --show-error "${ISSUER%/}/.well-known/openid-configuration" \
  | jq '{issuer, jwks_uri, authorization_endpoint, token_endpoint,
         device_authorization_endpoint, grant_types_supported, id_token_signing_alg_values_supported}'
```

The expected provider issuer is `https://auth.olsen.cloud/application/o/prod-openbao/`;
compare the returned issuer with the generated value rather than hard-coding a
mismatch. Discovery and JWKS must be reachable from the server as well as the
workstation. Check provider-specific grant configuration in Authentik; global
discovery advertisements alone are insufficient.

Sources: [Authentik OAuth/OIDC, scopes/signing/refresh](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/),
[device-flow prerequisite and administrative steps](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/device_code/),
[OpenBao OIDC redirects and roles](https://openbao.org/docs/auth/jwt/).

## Custody and safe operator shell

Use a trusted interactive Bash session with no terminal recording, shell tracing,
CI job, shared clipboard history or debug HTTP proxy. Use an encrypted workstation
volume with encrypted/disabled swap and no core dumps. A shell/environment token
can still be read by same-user processes or root: workstation trust is required.
Never pass bearer tokens, client secrets or shares as command arguments; never
write a plaintext `.bao-token`, `.vault-token`, init JSON or token export file.
Never `kubectl exec ... env BAO_TOKEN=...` (exec arguments can be audited).

```bash
set +x
set -o pipefail
umask 077
ulimit -c 0
unset BAO_TOKEN VAULT_TOKEN BAO_SKIP_VERIFY VAULT_SKIP_VERIFY
export BAO_ADDR=https://openbao.olsen.cloud
```

All login examples use `-no-store -token-only` inside command substitution: the
native CLI returns the bearer token directly to shell memory, not a helper file
or terminal. `-no-store` alone still prints the token! Never run plain `bao login`
or unfiltered `bao token lookup` during a recorded session.
[Native login flags](https://openbao.org/docs/commands/login/),
[native stdin inputs](https://openbao.org/docs/commands/write/).

## One-time initialization and every-restart unseal

**Requires separate approval; irreversible initial key creation.** First confirm
`bao status` says uninitialized and that this is genuinely new, empty storage,
not a lost/misattached existing PVC. Do not initialize to troubleshoot a missing
volume or restore.

Approved homelab custody is one native unseal key (`1` share, threshold `1`) in
Bitwarden, plus an encrypted offline recovery copy. This is single-operator
custody, not separation of duties: anyone with the key can unseal the database.
If Bitwarden depends on this cluster, recovery must also work while the cluster
is down.

Before initialization, provide the operator's **verified public** OpenPGP
encryption key as `root-operator.gpg` (binary/base64 public export). Its private
key must already be recoverable independently of OpenBao, with tested offline
access. The directory below is outside Git and on the approved encrypted custody
volume. Verify the recipient fingerprint through a separate channel. Do not
initialize until the encrypted output can be recovered and imported into Bitwarden.

```bash
CUSTODY_DIR="$HOME/.local/share/openbao-custody"
# Provision/mount the approved encrypted custody location and public keys first.
test -r "$CUSTODY_DIR/root-operator.gpg" && \
  test ! -e "$CUSTODY_DIR/init-encrypted.json" && \
  bao operator init -key-shares=1 -key-threshold=1 \
    -pgp-keys="$CUSTODY_DIR/root-operator.gpg" \
    -root-token-pgp-key="$CUSTODY_DIR/root-operator.gpg" -format=json \
    > "$CUSTODY_DIR/init-encrypted.json"
```

Both the unseal key and initial root token are PGP-encrypted **by OpenBao before
the response leaves the server**; the file contains ciphertext, not plaintext
init output. Do not omit either PGP option. Recover the unseal key through the
trusted operator interface and save it in Bitwarden, never in chat or agent tool
output. Keep an independently recoverable encrypted offline copy and record the
recipient fingerprint/cluster ID separately. Verify recovery before depending on
the service. Do not put the envelope, private key, unseal key or root token in Git,
Kubernetes Secrets, logs or this ticket.
[Initialization and PGP flags](https://openbao.org/docs/commands/operator/init/).

Recover the key from Bitwarden or the offline custody copy and enter it in the
**hidden prompt**, never in command history:

```bash
# Requires approval; one key submission is sufficient.
bao operator unseal
# Read-only, expect Initialized=true, Sealed=false.
bao status
```

Repeat after **every** server process restart, pod recreation, node reboot or
upgrade. Do not initialize again. Do not store the unseal key in the cluster.
[Native hidden-prompt unseal](https://openbao.org/docs/commands/operator/unseal/).

For approved one-time bootstrap, the root operator decrypts only into shell memory:

```bash
BAO_TOKEN="$(jq -er '.root_token' "$CUSTODY_DIR/init-encrypted.json" \
  | base64 --decode | gpg --decrypt)" && test -n "$BAO_TOKEN" && export BAO_TOKEN
```

Do not display this variable. The initial token is non-expiring and must be
revoked after verified alternative admin access. Preserve unseal custody, not a
standing root session; later emergency root generation is the native recovery
[`bao operator generate-root`](https://openbao.org/docs/commands/operator/generate-root/)
ceremony, separately approved, with encrypted recipient handling.

## Native OIDC bootstrap and policy separation

**All writes below require approval.** Use the short-lived bootstrap root session
only for setup, then test an independently acquired platform-admin token before
revoking root. Do not add `root` or a wildcard admin policy to the app's default
users. There is deliberately no default OIDC role.

```bash
bao auth enable -path=oidc oidc
# Generated OAuth credentials travel Kubernetes API -> jq -> native CLI stdin.
# Do not use tee, kubectl -v, set -x or echo this pipeline's data.
kubectl -n prod get secret openbao-oidc-credentials -o json \
  | jq -ce '.data | {
      oidc_discovery_url: (.issuer | @base64d),
      bound_issuer: (.issuer | @base64d),
      oidc_client_id: (.clientId | @base64d),
      oidc_client_secret: (.clientSecret | @base64d),
      jwt_supported_algs: ["RS256"]
    }' \
  | bao write auth/oidc/config -
bao auth tune -default-lease-ttl=1h -max-lease-ttl=1h oidc/
```

Re-run the credential pipeline only after approved client-secret rotation; the
provider operator updates its Secret, **not** OpenBao's internal auth config.
No runtime Secret watcher/bootstrap controller is installed here.
[OIDC config/role API](https://openbao.org/docs/api/auth/jwt/).

The `platform-admin` policy is intentionally a **trusted security-administrator**
role: it can manage OIDC roles and ACL policies, mount engines, revoke sessions
and restore snapshots. Policy/auth-management authority can escalate privileges;
it is not a safe application policy. It does not directly grant all secret paths
and is assigned only to the separately approved exact admin `sub` **and** admin
group. Root remains a separate emergency recovery/bootstrap capability.

```bash
bao policy write platform-admin - <<'HCL'
path "sys/auth" { capabilities = ["read"] }
path "auth/oidc/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/policies/acl" { capabilities = ["list"] }
path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list"] }
path "sys/mounts" { capabilities = ["read"] }
path "sys/mounts/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }
path "ssh/config/ca" { capabilities = ["create", "read", "update"] }
path "ssh/roles/*" { capabilities = ["create", "read", "update", "delete"] }
path "sys/storage/raft/configuration" { capabilities = ["read"] }
path "sys/storage/raft/snapshot" { capabilities = ["read", "update", "sudo"] }
path "sys/storage/raft/snapshot-force" { capabilities = ["update", "sudo"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
path "auth/token/revoke-accessor" { capabilities = ["update"] }
HCL

# A concrete isolated project example, not a global shared-user grant.
bao secrets enable -path=projects kv-v2
bao policy write project-reader - <<'HCL'
path "projects/data/homelab-config/*" { capabilities = ["read"] }
path "projects/metadata/homelab-config" { capabilities = ["list"] }
path "projects/metadata/homelab-config/*" { capabilities = ["read", "list"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
path "sys/capabilities-self" { capabilities = ["update"] }
HCL
```

Approve this example project's name and user before creating it, or substitute a
reviewed real project consistently in policy and role names. For a project writer,
create a separate reviewed policy on **only** that project's `data/` paths with
`create`/`update` (and `patch` only if needed), and an independently subject-bound
writer role. Do not grant `metadata` delete, version destroy, other project paths,
engine/auth/policy administration or token creation to a reader/writer by default.
Workload identities need their own narrow native auth method/role (for example
Kubernetes auth bound to the specific service account/namespace); human OIDC tokens
and the provider's client secret are not workload credentials. None are installed
by these examples. [KV-v2 API policy paths](https://openbao.org/docs/secrets/kv/kv-v2/),
[policy semantics](https://openbao.org/docs/concepts/policies/).

Obtain the exact immutable Authentik user UUID `sub` and emitted group strings via
the approved admin view. Group references such as `shared/admin` are Kubernetes
object references, **not necessarily** the string in an ID-token `groups` claim.
Supply the actual claims; do not guess `admin`, a username or an email. All four
roles are restricted by both exact subject and group. Creating a second admin or
project user requires a separately reviewed role/subject, not removing bindings.

```bash
read -r -p 'Approved platform administrator UUID sub: ' ADMIN_SUB
read -r -p 'Exact emitted administrator group: ' ADMIN_GROUP
read -r -p 'Approved project reader UUID sub: ' PROJECT_SUB
read -r -p 'Exact emitted project/app access group: ' PROJECT_GROUP
test -n "$ADMIN_SUB" && test -n "$ADMIN_GROUP" && \
  test -n "$PROJECT_SUB" && test -n "$PROJECT_GROUP"
```

Stop on any failed/empty input; do not run the following loop until all four
identifiers have been independently reviewed. Browser roles use the UI/localhost
callbacks. OpenBao 2.7.2 also requires a nonempty redirect allowlist when creating
device roles, although the device flow does not use a callback
([pinned role validation](https://github.com/openbao/openbao/blob/v2.7.2/internal/builtin/credential/jwt/path_role.go#L707-L711)).
No provider token metadata is returned, no verbose logging, no period, no default
policy and no renewal capability is granted by these policies.

```bash
for PRINCIPAL in platform project; do
  if [ "$PRINCIPAL" = platform ]; then
    SUBJECT="$ADMIN_SUB"; GROUP="$ADMIN_GROUP"; POLICY=platform-admin
  else
    SUBJECT="$PROJECT_SUB"; GROUP="$PROJECT_GROUP"; POLICY=project-reader
  fi
  for FLOW in browser device; do
    jq -n --arg subject "$SUBJECT" --arg group "$GROUP" \
      --arg policy "$POLICY" --arg flow "$FLOW" '{
        role_type: "oidc", user_claim: "sub", groups_claim: "groups",
        bound_subject: $subject, bound_claims: {groups: [$group]},
        bound_claims_type: "string", oidc_scopes: ["profile", "email"],
        callback_mode: (if $flow == "device" then "device" else "client" end),
        allowed_redirect_uris: [
          "https://openbao.olsen.cloud/ui/vault/auth/oidc/oidc/callback",
          "http://localhost:8250/oidc/callback"],
        token_policies: [$policy], token_no_default_policy: true,
        token_type: "service", token_ttl: "1h", token_max_ttl: "1h",
        token_explicit_max_ttl: "1h", token_period: 0,
        verbose_oidc_logging: false
      }' | bao write "auth/oidc/role/$PRINCIPAL-$FLOW" - || break 2
  done
done
unset ADMIN_SUB ADMIN_GROUP PROJECT_SUB PROJECT_GROUP SUBJECT GROUP POLICY PRINCIPAL FLOW
```

`token_explicit_max_ttl=1h` fixes the maximum lifetime from issuance, even if a
privileged caller later requests a native renewal. The server may issue a shorter
TTL. Do not promise refresh, background renewal or persistent sessions: repeat
native login when expired. A service token may report `renewable=true`; that is
not an entitlement to extend beyond the explicit cap. Removing provider access,
logging out of Authentik, or changing a role does not by itself prove that an
already-issued OpenBao token has been revoked. Use native token revocation (an
approved admin can use a recorded token accessor, not a bearer argument) when
immediate termination is required. [Token TTL/revocation](https://openbao.org/docs/concepts/tokens/).

## Browser/device login and acceptance after approved setup

Perform in a **second** trusted shell with the safe-shell setup above, retaining
bootstrap access only until success is proven. Each successful login mutates
server session state and needs approval as part of this operational check.

```bash
# Browser CLI: local loopback receiver; auth URL/status go to stderr, token to memory.
BAO_TOKEN="$(bao login -method=oidc -path=oidc -no-store -token-only \
  role=platform-browser)" && test -n "$BAO_TOKEN" && export BAO_TOKEN
# Read-only; deliberately filter out the token ID from lookup output.
bao token lookup -format=json | jq '.data | {policies, ttl, explicit_max_ttl, renewable}'
bao operator raft list-peers
```

For the UI, open the private HTTPS address, select OIDC, enter `platform-browser`
or `project-browser`, and complete Authentik login. Never paste the bootstrap
root token into the UI. Check UI session handling on a trusted browser and log
out when finished; CLI no-store flags do not control browser storage.

For a headless client, verify the Authentik Brand prerequisite first, then:

```bash
unset BAO_TOKEN
BAO_TOKEN="$(bao login -method=oidc -path=oidc -no-store -token-only \
  role=project-device callbackmode=device skip_browser=true)" \
  && test -n "$BAO_TOKEN" && export BAO_TOKEN
bao token lookup -format=json | jq '.data | {policies, ttl, explicit_max_ttl, renewable}'
bao token capabilities projects/data/homelab-config/verification
bao token capabilities projects/data/another-project/verification
bao token capabilities sys/policies/acl/platform-admin
```

Native CLI prints the short-lived verification URL/code to stderr and polls
OpenBao's native OIDC endpoint; the user authorizes only a login they initiated,
using a trusted second device if needed. Do not record/repost those URLs/codes.
Expected project policy only, TTL no greater than 3600 seconds, `read` on its
project and `deny` on other projects and admin policy. Also exercise
`project-browser` and `platform-device` with their respective authorized humans.
Verify unauthorized subject/group denial through login, not just policy inspection.
Do not weaken claim constraints to make a smoke check pass. Record results without
bearer tokens or provider payloads; no successful browser/device smoke is claimed
until actually exercised after approved deployment.

An existing Authentik SSO session may satisfy login with no new password or MFA
prompt. OIDC/device login is **not proof of fresh MFA**. If fresh MFA is required,
an Authentik administrator must configure and test the native authentication/
step-up flow and relevant policies with approval; that requirement is not
implemented by the chart. [Authentik MFA stages](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate/).

After independently verified admin browser/device access, return to the original
bootstrap shell and **with approval** revoke the initial root token:

```bash
bao token revoke -self
unset BAO_TOKEN
```

End every operator session the same way (revoking that session's token), then exit
the shell. Keep only encrypted custody material. Do not claim revocation succeeded
if the command failed. [Root-token guidance](https://openbao.org/docs/concepts/tokens/#root-tokens).

## Native SSH user-certificate engine

The server supports the native SSH engine, but **the Helm chart does not enable
it**. With separate approval, configure it after init/unseal using bootstrap root
or an independently verified `platform-admin` session. This is a user-certificate
CA, not OTP, not a private-key generator for users, and not host-certificate setup.
The CA private key is generated inside OpenBao and stored under its encryption
barrier; users' private keys never leave their workstation.

**Read-only:** inspect `bao secrets list -detailed` and, if `ssh/` already exists,
`bao read ssh/config/ca`. Do not replace an existing engine/CA; review its roles,
issuer/trust fingerprint and reuse it only if approved. CA generation below is
for a confirmed new mount without CA material; repeating it changes the default
CA/trust and is not an idempotent health check.

```bash
# Requires approval; run enable only when ssh/ is absent.
bao secrets enable -path=ssh ssh
# Requires explicit new-CA approval; returns only the public key.
bao write ssh/config/ca generate_signing_key=true key_type=rsa key_bits=4096
# Read-only: capture and fingerprint the PUBLIC trust anchor outside Git.
bao read -field=public_key ssh/config/ca > "$CUSTODY_DIR/ssh-user-ca.pub"
ssh-keygen -lf "$CUSTODY_DIR/ssh-user-ca.pub"
```

Record the public CA fingerprint and issuer identity in the custody/change record.
Do not export the CA private key. The native `config/ca` endpoint sets the default
issuer; review native multi-issuer procedures separately for any later rotation.

Before allowing signing, obtain approval for the **actual existing non-root remote
account/principal** and target host set. No remote account name is assumed here:

```bash
read -r -p 'Approved existing non-root SSH account/principal: ' SSH_PRINCIPAL
[[ "$SSH_PRINCIPAL" =~ ^[a-z_][a-z0-9_-]*$ && "$SSH_PRINCIPAL" != root ]]
```

Stop if validation fails; never use `*`, empty principals, `root`, or a comma-list.
One narrowly named role grants this one reviewed account:

```bash
# Requires approval: short-lived, user-only, no forwarding extensions.
jq -n --arg principal "$SSH_PRINCIPAL" '{
  key_type: "ca", issuer_ref: "default", algorithm_signer: "rsa-sha2-512",
  allow_user_certificates: true, allow_host_certificates: false,
  allowed_users: $principal, default_user: $principal,
  allowed_users_template: false, allow_empty_principals: false,
  allowed_extensions: "permit-pty", default_extensions: {"permit-pty": ""},
  allowed_critical_options: "source-address", default_critical_options: {},
  allow_user_key_ids: false, allowed_user_key_lengths: {"ed25519": 0},
  ttl: "15m", max_ttl: "15m"
}' | bao write ssh/roles/homelab-user -

bao policy write ssh-homelab-user - <<'HCL'
path "ssh/sign/homelab-user" { capabilities = ["update"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
HCL
```

This signer policy has no `ssh/issue`, `ssh/creds`, CA/role administration, other
signing roles, project secret access or host-certificate permissions. It is not
attached to all app users or even all project readers. To authorize a separately
approved exact user/group, clone only the previously reviewed constrained OIDC
role settings, replacing identity bindings and policy (not widening them):

```bash
read -r -p 'Approved SSH signer UUID sub: ' SSH_SUB
read -r -p 'Exact emitted SSH signer access group: ' SSH_GROUP
test -n "$SSH_SUB" && test -n "$SSH_GROUP"
# Stop on failed/empty input; review both identifiers before running these writes.
for FLOW in browser device; do
  bao read -format=json "auth/oidc/role/project-$FLOW" \
    | jq -ce --arg subject "$SSH_SUB" --arg group "$SSH_GROUP" \
      '.data | del(.policies, .ttl, .max_ttl, .period)
       | .bound_subject = $subject | .bound_claims = {groups: [$group]}
       | .token_policies = ["ssh-homelab-user"]' \
    | bao write "auth/oidc/role/ssh-$FLOW" - || break
done
unset SSH_SUB SSH_GROUP FLOW
```

The SSH user logs in as `ssh-browser` or `ssh-device`, using the same native
no-store/token-only login pattern. They keep an encrypted/passphrase-protected
local key and submit only its public half:

```bash
# Local action, choose a strong passphrase at the native prompt.
test ! -e "$HOME/.ssh/openbao-homelab" && \
  ssh-keygen -t ed25519 -f "$HOME/.ssh/openbao-homelab"
# Requires approved native signing session and the same approved principal.
read -r -p 'Approved SSH account/principal for this role: ' SSH_PRINCIPAL
bao write -field=signed_key ssh/sign/homelab-user \
  public_key=@"$HOME/.ssh/openbao-homelab.pub" \
  valid_principals="$SSH_PRINCIPAL" cert_type=user ttl=15m \
  > "$HOME/.ssh/openbao-homelab-cert.pub"
ssh-keygen -Lf "$HOME/.ssh/openbao-homelab-cert.pub"
unset SSH_PRINCIPAL
```

Check the CA fingerprint, single intended principal, 15-minute validity and no
forwarding/host privileges. Re-signing needs a valid OpenBao session and is not
automatic. Certificate validity is separate from OpenBao token TTL: revoking the
OpenBao token stops new signing but does **not** revoke an already-issued SSH
certificate or terminate an established SSH session.

**No host trust/sshd changes or target login are authorized by this chart.**
Each host needs separately approved installation of the verified **public** CA
with `TrustedUserCAKeys`, restricted principal/account authorization and validated
sshd configuration. A user certificate is not host-scoped: every host trusting
this CA and accepting that principal could accept it. Limit host trust/principal
mapping to the reviewed target set; role `cidr_list` is not a CA host restriction.
Remote root/sudo access remains a separately reviewed OS policy, never implicit.
If immediate SSH revocation is needed, configure/rehearse host-side OpenSSH KRL/
revocation controls under separate approval; certificate TTL alone is not that
control. No target host is changed or claimed ready here.

The SSH CA private key, issuer, role and policy are included in native Raft
snapshots. Take a fresh encrypted/off-node snapshot after setup/rotation. Restoring
an older snapshot can restore an older CA; compare its fingerprint with the host
trust inventory before resuming signing, and never silently regenerate a lost CA.

Sources: [native signed SSH certificates](https://openbao.org/docs/secrets/ssh/signed-ssh-certificates/),
[SSH role/CA/sign API](https://openbao.org/docs/api/secret/ssh/),
[OpenSSH certificate/trust and revocation](https://man.openbsd.org/sshd).

## Secret consumption boundary

Use the native CLI/API and a project-specific policy. Secret values must enter
writes through stdin or protected encrypted source files, never command-line
`password=...` values; do not display secret reads into a recorded terminal. No
custom login wrapper, session broker or secondary token protocol is required.

A KV/static password injected into an application's environment or file does **not**
expire when the OpenBao login token expires. It remains available to that process
and valid at the upstream service until explicitly rotated/revoked there; KV
versioning is not a lease. Workload restarts/rotation and actual dynamic-secret
leases need separately designed native integrations. The chart does not migrate
existing application Secrets or promise automatic refresh/revocation.
[KV-v2](https://openbao.org/docs/secrets/kv/kv-v2/),
[leases](https://openbao.org/docs/concepts/lease/).

## Native Raft snapshots (manual, not configured automation)

**Requires approval:** take a snapshot using an approved platform-admin session.
The native snapshot API captures a coherent Raft state; copying live files from
`data-openbao-0` with Volsync Direct is not an application-consistent backup. Keep
snapshots off the node/PVC, encrypted and access-controlled, with timestamp,
checksum, server/chart/config versions, custody-key epoch and a restore record.
A snapshot is not usable recovery without the matching original unseal key.

On an already-mounted encrypted operator backup volume outside the repository:

```bash
read -r -p 'Mounted encrypted backup directory (absolute path): ' BACKUP_DIR
test -d "$BACKUP_DIR" && test -w "$BACKUP_DIR"
# Stop if the checks failed or this is not the approved encrypted/off-node volume.
SNAPSHOT="$BACKUP_DIR/openbao-$(date -u +%Y%m%dT%H%M%SZ).snap"
bao operator raft snapshot save "$SNAPSHOT" && sha256sum "$SNAPSHOT"
```

Treat the entire snapshot as sensitive, even though Raft's barrier encrypts secret
values. Store/deliver through the approved encrypted backup system; never commit,
attach to a ticket or store the only copy beside the Raft data. Define and approve
schedule, retention, delivery, failure alerting and isolated restore drills before
claiming a backup service/SLO. None are installed here.
[Snapshot commands](https://openbao.org/docs/commands/operator/raft/#snapshot),
[snapshot API and force semantics](https://openbao.org/docs/api/system/storage/raft/).

## Recovery and upgrades

Every recovery/upgrade is an **approved maintenance window with a single-node
outage**. First identify whether the original PVC is intact. An ordinary restart
needs the original PVC and manual unseal, not a snapshot restore. Do not remove
Raft peers, delete the data directory, rewrite `peers.json` or initialize again to
solve a routine sealed state.

### Restore over an intact, initialized server

1. Obtain approval for the exact snapshot/time and data-loss window: restore rolls
   back **all** stored secrets, policies, identities, auth configuration and token
   state. Quiesce consumers/writes; prevent competing ArgoCD or operator changes.
   Retain a fresh pre-restore snapshot and the original volume when available.
2. Verify the snapshot checksum/version/custody record and matching unseal key.
   Start the same server version/config and manually unseal. Acquire the approved
   admin session as above; the command below replaces live state.
3. **Requires explicit destructive-restore approval:**

   ```bash
   read -r -p 'Approved snapshot absolute path: ' RESTORE_SNAPSHOT
   test -r "$RESTORE_SNAPSHOT" && bao operator raft snapshot restore "$RESTORE_SNAPSHOT"
   unset BAO_TOKEN
   ```

4. Check `bao status`; unseal if sealed. Authenticate anew using
   the **restored** auth configuration; pre-restore tokens/configuration may no
   longer work. Check one Raft voter, intended policies, browser/device access and
   selected consumer reads before resuming writers. Snapshot credentials may be
   stale or externally revoked; coordinate upstream service rotations. Never
   assume restoring token state safely restores external leases.

### Lost PVC / replacement server

Restore to an isolated, non-public replacement with the recorded version/config,
no access to production consumers or external secret backends. Obtain explicit
approval before creating replacement storage and temporarily initializing it;
follow the same PGP-encrypted initialization and hidden-prompt unseal ceremony,
keeping temporary custody distinct from the original snapshot's custody. Its
bootstrap token authorizes the restore. A fresh cluster has different Shamir keys,
so normal restore rejects the snapshot; only after approval and confirming the
**original snapshot's unseal key is recoverable** use the native force option:

```bash
# Destructive; separate approval, isolated replacement only, not a default retry.
read -r -p 'Approved original snapshot absolute path: ' RESTORE_SNAPSHOT
test -r "$RESTORE_SNAPSHOT" && bao operator raft snapshot restore -force "$RESTORE_SNAPSHOT"
unset BAO_TOKEN
```

Force bypasses the seal-key consistency check; it does not decrypt the snapshot
or recover lost original keys. Check status and unseal with the **original**
snapshot-era unseal key, not the replacement-init key. Login uses snapshot-era auth
configuration. If that access is unavailable, use a separately approved native
generate-root ceremony. Keep temporary credentials encrypted until restore
outcome is established, then dispose of them under the custody procedure; they
are not an alternative key to the restored database. Rehearse this path isolated
before relying on it for recovery, and separately approve any production cutover.
[Native force implementation, pinned 2.7.2](https://github.com/openbao/openbao/blob/v2.7.2/internal/command/operator_raft_snapshot_restore.go),
[integrated-storage recovery](https://openbao.org/docs/concepts/integrated-storage/).

### Upgrade / rollback

1. Read release/upgrade notes for **every intervening version**, review image digest,
   chart/schema changes and config compatibility. No automatic runtime upgrade is
   safe without a snapshot and access to the unseal key.
2. Take an off-node native snapshot and record the old chart/image/config. Rehearse
   upgrade and restore in an isolated environment with external network access
   blocked so restored dynamic leases cannot revoke production credentials.
3. After approval, update pinned dependency/image in Git and sync through ArgoCD.
   The StatefulSet uses **OnDelete**, so syncing a new template does not itself
   restart the server. In the maintenance window, explicitly approve graceful pod
   replacement (`kubectl -n prod delete pod openbao-0`), preserving `data-openbao-0`.
   Never force-delete or delete the PVC. Expect downtime until the operator
   manually unseals the recreated server with the key from approved custody.
4. Check version, unsealed state, one Raft voter, mTLS boundary, native browser and
   device login, least-privilege denial and actual consumer access. Resume writes
   only after successful checks. Do not describe these checks as already passed.
5. Rollback is **not** just an old image: OpenBao does not guarantee backward data
   compatibility. With approval, preserve failed-upgrade data, restore the matching
   pre-upgrade snapshot into the recorded previous version/config using the
   recovery procedure, account for lost writes and approve cutover. Never run an
   old binary against a potentially migrated live data directory.

Sources: [official upgrade guide](https://openbao.org/docs/upgrading/),
[OpenBao 2.7.2 release](https://github.com/openbao/openbao/releases/tag/v2.7.2),
[native device CLI, pinned 2.7.2](https://github.com/openbao/openbao/blob/v2.7.2/internal/builtin/credential/jwt/cli.go).
